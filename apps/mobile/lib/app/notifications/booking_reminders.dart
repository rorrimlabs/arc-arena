/// Orchestrates booking reminders (spec §23): resolves a booking's display
/// details, turns them into reminder payloads via the pure
/// [buildBookingReminders] builder, and schedules/cancels them through the
/// [NotificationService].
///
/// De-duplication: reminder ids are deterministic (see [reminderId]), so a
/// reschedule replaces the old reminder, and the start-up sweep
/// (`refreshReminders`) removes what an earlier run left behind — reopening
/// the app never stacks duplicate reminders (spec §23, §33).
library;

import 'package:arena_ops/app/notifications/device_time.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/repositories/customer_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class BookingReminders {
  BookingReminders({
    required this.service,
    required this.bookings,
    required this.customers,
    required this.catalog,
    required this.clock,
    this.policy = ReminderPolicy.defaults,
  });

  final NotificationService service;
  final BookingRepository bookings;
  final CustomerRepository customers;
  final CatalogRepository catalog;
  final Clock clock;
  final ReminderPolicy policy;

  /// Booking ids this run has reminders scheduled for, so [reconcile] can
  /// cancel those that were cancelled, checked in or moved elsewhere.
  final Set<String> _scheduled = {};

  /// One reminder change at a time, reading the booking when it runs — a
  /// refresh can never put back a reminder for a booking cancelled meanwhile.
  Future<void> _last = Future.value();

  /// Runs [work] in turn; true when it finished without an error.
  Future<bool> _serial(String what, Future<void> Function() work) {
    final done = _last.then((_) => work()).then((_) => true, onError: (
      Object e,
    ) {
      debugPrint('BookingReminders.$what failed: $e');
      return false;
    });
    _last = done;
    return done;
  }

  /// Runs [work] with no reminder change in between (the start-up sweep).
  Future<bool> exclusive(Future<void> Function() work) =>
      _serial('exclusive', work);

  /// Notification ids of everything this run has scheduled (start-up sweep).
  Set<int> get scheduledIds => {
        for (final id in _scheduled) ...[reminderId(id, 0), reminderId(id, 1)],
      };

  /// Schedule (or reschedule) the reminders for one booking, as it is in the
  /// database now; one no longer upcoming, or with its reminder turned off,
  /// has them removed. Never throws — a reminder problem must not break
  /// creating or managing the booking.
  Future<void> scheduleFor(Booking booking) =>
      _serial('scheduleFor(${booking.id})', () async {
        final fresh = await bookings.getById(booking.id);
        if (fresh == null || !_upcoming(fresh)) {
          await _cancel(booking.id);
          return;
        }
        await _schedule(fresh);
      });

  /// Cancel both reminder slots for a booking (on cancel, check-in, or no-show).
  Future<void> cancelFor(String bookingId) =>
      _serial('cancelFor($bookingId)', () => _cancel(bookingId));

  /// Bring the reminders in line with the bookings this device knows now:
  /// every upcoming one is (re)scheduled in place — the same id replaces the
  /// old reminder, so nothing due is ever removed before its replacement
  /// exists — and those of bookings no longer upcoming (cancelled, moved,
  /// reminder turned off) that have not rung yet are cancelled. One that rang
  /// stays in the tray. Run after sync brings changes, on resume and at
  /// start-up. True when it completed.
  Future<bool> reconcile() => _serial('reconcile', () async {
        final upcoming = (await bookings.upcoming()).where(_upcoming).toList()
          // Latest first: iOS keeps only the 64 most recently set
          // notifications, so the soonest ones are set last.
          ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
        final ids = {for (final b in upcoming) b.id};
        for (final id in _scheduled.difference(ids).toList()) {
          _scheduled.remove(id);
          for (final slot in [reminderId(id, 0), reminderId(id, 1)]) {
            await _cancelIfLater(slot);
          }
        }
        for (final b in upcoming) {
          await _schedule(b);
        }
      });

  bool _upcoming(Booking b) =>
      b.status == BookingStatus.booked &&
      b.reminderStatus != ReminderStatus.off &&
      b.scheduledStart.toUtc().isAfter(clock.now());

  /// When (app clock) each reminder this run set is due, by notification id.
  final Map<int, DateTime> _ringsAt = {};

  /// Cancels [slot] only if this run set it to ring later than now: one due
  /// or already rung is left alone, so it still rings and stays in the tray.
  Future<void> _cancelIfLater(int slot) async {
    final setFor = _ringsAt[slot];
    if (setFor != null && setFor.isAfter(clock.now())) {
      await service.cancel(slot);
      _ringsAt.remove(slot);
    }
  }

  Future<void> _schedule(Booking booking) async {
    try {
      _scheduled.add(booking.id); // before, so the start-up sweep keeps it
      final plans = await _plansFor(booking);
      // A slot left out (moved so its time has passed) must not ring the
      // old time.
      final kept = {for (final p in plans) p.id};
      for (final slot in [reminderId(booking.id, 0), reminderId(booking.id, 1)]) {
        if (!kept.contains(slot)) await _cancelIfLater(slot);
      }
      for (final plan in plans) {
        await service.schedule(onDeviceClock(plan, clock));
        _ringsAt[plan.id] = plan.fireAtUtc;
      }
    } catch (e) {
      debugPrint('scheduleFor(${booking.id}) failed: $e');
    }
  }

  Future<void> _cancel(String bookingId) async {
    _scheduled.remove(bookingId);
    _ringsAt
      ..remove(reminderId(bookingId, 0))
      ..remove(reminderId(bookingId, 1));
    try {
      await service.cancel(reminderId(bookingId, 0));
      await service.cancel(reminderId(bookingId, 1));
    } catch (e) {
      debugPrint('cancelFor($bookingId) failed: $e');
    }
  }

  Future<List<ReminderPlan>> _plansFor(Booking booking) async {
    final customer = booking.customerId == null
        ? null
        : await customers.getById(booking.customerId!);
    final game =
        booking.gameId == null ? null : await catalog.gameById(booking.gameId!);
    final activities = await catalog.activities();
    final activityLabel = activities
            .firstWhereOrNull((a) => a.code == booking.activityCode)
            ?.name ??
        booking.activityCode;
    String? resName;
    if (booking.resourceId != null) {
      resName = (await catalog.resources())
          .firstWhereOrNull((r) => r.id == booking.resourceId)
          ?.name;
    }
    return buildBookingReminders(
      booking: booking,
      customerName: customer?.name ?? 'Guest',
      activityLabel: activityLabel,
      gameName: game?.name,
      resourceName: resName,
      policy: policy,
      now: clock.now(),
    );
  }
}
