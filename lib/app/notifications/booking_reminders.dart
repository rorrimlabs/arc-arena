/// Orchestrates booking reminders (spec §23): resolves a booking's display
/// details, turns them into reminder payloads via the pure
/// [buildBookingReminders] builder, and schedules/cancels them through the
/// [NotificationService].
///
/// De-duplication: reminder ids are deterministic (see [reminderId]), and
/// [syncUpcoming] cancels everything before rescheduling, so reopening the app
/// never stacks duplicate reminders (spec §23, §33).
library;

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

  /// Schedule (or reschedule) the reminders for one booking. Never throws — a
  /// reminder problem must not break creating or managing the booking.
  Future<void> scheduleFor(Booking booking) async {
    if (booking.status != BookingStatus.booked) return;
    try {
      for (final plan in await _plansFor(booking)) {
        await service.schedule(plan);
      }
    } catch (e) {
      debugPrint('scheduleFor(${booking.id}) failed: $e');
    }
  }

  /// Cancel both reminder slots for a booking (on cancel, check-in, or no-show).
  Future<void> cancelFor(String bookingId) async {
    try {
      await service.cancel(reminderId(bookingId, 0));
      await service.cancel(reminderId(bookingId, 1));
    } catch (e) {
      debugPrint('cancelFor($bookingId) failed: $e');
    }
  }

  /// Reconcile every scheduled reminder with the current upcoming bookings.
  /// Called on startup: cancels all, then reschedules only still-booked future
  /// bookings — so restarting never duplicates or strands a reminder.
  Future<void> syncUpcoming() async {
    try {
      await service.cancelAll();
      final upcoming = await bookings.upcoming();
      final now = clock.now();
      for (final b in upcoming) {
        if (b.status == BookingStatus.booked &&
            b.scheduledStart.toUtc().isAfter(now)) {
          await scheduleFor(b);
        }
      }
    } catch (e) {
      debugPrint('syncUpcoming failed: $e');
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
