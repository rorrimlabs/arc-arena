/// Application-layer booking orchestration (spec §18–§23). Game-first
/// availability resolution on create; converts a booking into a real session on
/// check-in, keeping the booking as the planned record.
library;

import 'package:arena_ops/app/controllers/pad_board_loader.dart';
import 'package:arena_ops/app/notifications/booking_reminders.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/group_session_repository.dart';
import 'package:arena_ops/domain/repositories/session_repository.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/services/booking_availability_service.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class BookingDraft {
  const BookingDraft({
    required this.customerId,
    required this.activityCode,
    required this.date,
    required this.startMinuteOfDay,
    required this.durationMinutes,
    this.gameId,
    this.resourceId, // null = any compatible system
    this.playersRequired,
    this.controllerRequirement,
    this.notes,
    this.editingId,
  });

  final String customerId;
  final String activityCode;
  final IstDate date;
  final int startMinuteOfDay;
  final int durationMinutes;
  final String? gameId;
  final String? resourceId;
  final int? playersRequired;
  final int? controllerRequirement;

  /// Free-text staff note ("birthday party, needs 2 tables").
  final String? notes;

  /// Set when amending an existing booking — the conflict check then ignores
  /// the booking's own slot so it never clashes with itself.
  final String? editingId;
}

/// What a check-in would do right now (see [BookingActions.planCheckIn]).
@immutable
class CheckInPlan {
  const CheckInPlan({
    required this.resource,
    required this.scheduledEnd,
    required this.usesControllers,
    this.requestedControllers,
    this.gameName,
    this.gameMaxLocalPlayers,
    this.alternatives = false,
  });

  final Resource resource;
  final DateTime scheduledEnd;
  final bool usesControllers;

  /// Controllers the booking asked for (null when it did not say).
  final int? requestedControllers;
  final String? gameName;
  final int? gameMaxLocalPlayers;

  /// True for an any-system booking: the station was chosen now.
  final bool alternatives;
}

class BookingActions {
  BookingActions({
    required this.bookings,
    required this.sessions,
    required this.catalog,
    required this.clock,
    this.reminders,
    this.availability = const BookingAvailabilityService(),
    this.groups,
    this.boards,
    this.padSelection = const PadSelection(),
  });

  final BookingRepository bookings;
  final SessionRepository sessions;
  final CatalogRepository catalog;
  final Clock clock;

  /// Schedules/cancels offline booking reminders (spec §23). Optional so the
  /// controller can be built without notifications (e.g. in tests).
  final BookingReminders? reminders;
  final BookingAvailabilityService availability;

  /// Open group assignments hold stations too; optional for older callers.
  final GroupSessionRepository? groups;

  /// The controller inventory as one station sees it. With it, check-in
  /// validates (and can borrow) specific pads exactly like New Session;
  /// without it, check-in is count-only (the repository still refuses more
  /// controllers than are free at the station).
  final PadBoardLoader? boards;
  final PadSelection padSelection;

  /// Active-session + existing-booking occupancy over [window]. Unassigned
  /// (any-system) bookings do not block a specific resource until check-in.
  Future<List<Occupancy>> _occupancies(UtcInterval window,
      {String? excludeBookingId}) async {
    final active = await sessions.active();
    final booked = await bookings.overlapping(window.start, window.end);
    final groupActive = await groups?.activeGroups() ?? const [];
    return [
      for (final a in active)
        Occupancy(
          resourceId: a.current.resourceId,
          interval: UtcInterval(a.current.startedAt, a.session.scheduledEndAt),
          isBooking: false,
        ),
      // A station a group is playing on is just as busy (group feature §7).
      for (final g in groupActive)
        for (final a in g.openAssignments)
          Occupancy(
            resourceId: a.resourceId,
            interval: UtcInterval(a.startedAt, g.group.scheduledEndAt),
            isBooking: false,
            label: 'group',
          ),
      for (final b in booked)
        if (b.resourceId != null && b.id != excludeBookingId)
          Occupancy(
            resourceId: b.resourceId!,
            interval: UtcInterval(b.scheduledStart, b.scheduledEnd),
            isBooking: true,
          ),
    ];
  }

  Future<Map<String, GameAvailability>?> _compat(String? gameId) async {
    if (gameId == null) return null;
    return {
      for (final rf in await catalog.resourcesForGame(gameId)) rf.resource.id: rf.status,
    };
  }

  /// Candidate systems for a draft (for showing the list before confirming).
  Future<List<Resource>> candidateSystems(BookingDraft d) async {
    final window = bookingWindow(
      date: d.date,
      startMinuteOfDay: d.startMinuteOfDay,
      durationMinutes: d.durationMinutes,
    );
    final game = d.gameId == null ? null : await catalog.gameById(d.gameId!);
    return availability.availableSystems(
      window: window,
      resources: await catalog.resources(),
      occupancies: await _occupancies(window),
      requireActivityCode: d.activityCode,
      compatibility: await _compat(d.gameId),
      gameMaxLocalPlayers: game?.maxLocalPlayers,
      playersRequired: d.playersRequired,
    );
  }

  Future<Result<Booking>> createBooking(BookingDraft d) async {
    final window = bookingWindow(
      date: d.date,
      startMinuteOfDay: d.startMinuteOfDay,
      durationMinutes: d.durationMinutes,
    );
    final resources = await catalog.resources();
    final game = d.gameId == null ? null : await catalog.gameById(d.gameId!);
    final compat = await _compat(d.gameId);
    final occ = await _occupancies(window, excludeBookingId: d.editingId);

    if (d.resourceId != null) {
      final matches = resources.where((r) => r.id == d.resourceId).toList();
      if (matches.isEmpty) {
        return const Err(Failure(message: 'Unknown system.', code: 'no_resource'));
      }
      final check = availability.checkSpecific(
        resource: matches.first,
        window: window,
        occupancies: occ,
        requireActivityCode: d.activityCode,
        gameName: game?.name,
        compatibility: compat,
        gameMaxLocalPlayers: game?.maxLocalPlayers,
        playersRequired: d.playersRequired,
      );
      if (check.isErr) return Err(check.failureOrNull!);
    } else {
      final avail = availability.availableSystems(
        window: window,
        resources: resources,
        occupancies: occ,
        requireActivityCode: d.activityCode,
        compatibility: compat,
        gameMaxLocalPlayers: game?.maxLocalPlayers,
        playersRequired: d.playersRequired,
      );
      if (avail.isEmpty) {
        return const Err(Failure(
          message: 'No compatible system is available for that time.',
          fix: 'Try another time or game.',
          code: 'no_availability',
        ));
      }
    }

    final existing =
        d.editingId == null ? null : await bookings.getById(d.editingId!);
    final draft = Booking(
      id: d.editingId ?? '',
      customerId: d.customerId,
      activityCode: d.activityCode,
      gameId: d.gameId,
      resourceId: d.resourceId,
      scheduledStart: window.start,
      scheduledEnd: window.end,
      playersRequired: d.playersRequired,
      controllerRequirement: d.controllerRequirement,
      status: existing?.status ?? BookingStatus.booked,
      notes: d.notes,
      reminderStatus: existing?.reminderStatus ?? ReminderStatus.scheduled,
      createdAt: existing?.createdAt ?? clock.now(),
      updatedAt: clock.now(),
    );

    final saved = existing == null
        ? await bookings.create(draft)
        : await bookings.update(draft);

    // Reschedule from scratch so an amended time never leaves the old
    // reminder behind (spec §23).
    if (existing != null) await reminders?.cancelFor(saved.id);
    await reminders?.scheduleFor(saved);
    return Ok(saved);
  }

  /// Amend an existing booking. Runs the same conflict checks as creating one,
  /// minus the booking's own slot.
  Future<Result<Booking>> updateBooking(BookingDraft draft) {
    assert(draft.editingId != null, 'updateBooking needs the booking id');
    return createBooking(draft);
  }

  /// Where and how a booked customer would be seated right now: the station
  /// (the booked one, or the best free compatible one for an any-system
  /// booking), the session end, and the controllers the booking asked for.
  /// Nothing is written — the check-in sheet shows this, lets staff pick the
  /// physical pads, then calls [checkIn].
  Future<Result<CheckInPlan>> planCheckIn(Booking booking,
      {String? preferResourceId}) async {
    if (booking.customerId == null) {
      return const Err(Failure(
        message: 'This booking has no customer.',
        code: 'no_customer',
      ));
    }
    final now = clock.now();
    final duration = booking.scheduledEnd.difference(booking.scheduledStart);
    final scheduledEnd =
        now.isBefore(booking.scheduledEnd) ? booking.scheduledEnd : now.add(duration);
    final window = UtcInterval(now, scheduledEnd);

    final resources = await catalog.resources();
    final game = booking.gameId == null ? null : await catalog.gameById(booking.gameId!);
    final compat = await _compat(booking.gameId);
    final occ = await _occupancies(window, excludeBookingId: booking.id);
    final activity = (await catalog.activities())
        .where((a) => a.code == booking.activityCode)
        .firstOrNull;
    final usesControllers = activity?.usesControllers ?? false;
    final wanted = booking.controllerRequirement ?? booking.playersRequired;

    Result<void> fits(Resource r) => availability.checkSpecific(
          resource: r,
          window: window,
          occupancies: occ,
          requireActivityCode: booking.activityCode,
          gameName: game?.name,
          compatibility: compat,
          gameMaxLocalPlayers: game?.maxLocalPlayers,
          playersRequired: booking.playersRequired,
        );

    Resource resolved;
    final fixedId = booking.resourceId ?? preferResourceId;
    if (fixedId != null) {
      final matches = resources.where((r) => r.id == fixedId).toList();
      if (matches.isEmpty) {
        return const Err(Failure(message: 'Unknown system.', code: 'no_resource'));
      }
      final check = fits(matches.first);
      if (check.isErr) return Err(check.failureOrNull!);
      resolved = matches.first;
    } else {
      final avail = availability.availableSystems(
        window: window,
        resources: resources,
        occupancies: occ,
        requireActivityCode: booking.activityCode,
        compatibility: compat,
        gameMaxLocalPlayers: game?.maxLocalPlayers,
        playersRequired: booking.playersRequired,
      );
      if (avail.isEmpty) {
        return const Err(Failure(
          message: 'No compatible system is free right now.',
          fix: 'Free a system or pick another.',
          code: 'no_availability',
        ));
      }
      resolved = avail.first;
      // Prefer a system that already has the booked controllers free, so the
      // party is not sent where pads would have to be borrowed.
      if (usesControllers && wanted != null && boards != null) {
        for (final r in avail) {
          final b = await boards!.load(resourceId: r.id, resourceName: r.name);
          if (!b.tracked || b.inventory.freeHere >= wanted) {
            resolved = r;
            break;
          }
        }
      }
    }
    return Ok(CheckInPlan(
      resource: resolved,
      scheduledEnd: scheduledEnd,
      usesControllers: usesControllers,
      requestedControllers: usesControllers ? wanted : null,
      gameName: game?.name,
      gameMaxLocalPlayers: game?.maxLocalPlayers,
      alternatives: booking.resourceId == null,
    ));
  }

  /// Check in a booked customer: re-check availability now and start a session
  /// linked to the booking (spec §22–§23). [controllers] are the physical pads
  /// staff picked on the check-in sheet (validated — and borrowed — exactly
  /// like New Session); without it the booking's controller count is used
  /// count-only, which the repository still checks against the free pads.
  Future<Result<Session>> checkIn(
    Booking booking, {
    ControllerChoice? controllers,
    String? resourceId,
  }) async {
    final planned = await planCheckIn(booking, preferResourceId: resourceId);
    if (planned.isErr) return Err(planned.failureOrNull!);
    final plan = planned.valueOrNull!;
    final resolved = plan.resource;
    final now = clock.now();

    var choice = controllers ?? ControllerChoice.count(plan.requestedControllers);
    if (!plan.usesControllers) choice = ControllerChoice.none;
    if (plan.usesControllers && boards != null) {
      final board =
          await boards!.load(resourceId: resolved.id, resourceName: resolved.name);
      final problem = padSelection.check(
        choice,
        board,
        maxLocalPlayers: plan.gameMaxLocalPlayers,
        gameName: plan.gameName,
      );
      if (problem != null) return Err(problem);
    }

    final snapshot = await catalog.currentSnapshot();
    final started = await sessions.start(StartSessionCommand(
      customerId: booking.customerId!,
      startedAt: now,
      scheduledEndAt: plan.scheduledEnd,
      snapshot: snapshot,
      resourceId: resolved.id,
      resourceName: resolved.name,
      activityCode: booking.activityCode,
      gameId: booking.gameId,
      controllerCount: plan.usesControllers ? choice.count : null,
      controllerIds: choice.padIdsOrNull,
      borrowControllerIds: choice.borrowIdsOrNull,
      bookingId: booking.id,
    ));
    if (started.isOk) {
      // The session start already checked the booking in, in the same
      // transaction (and the server does the same), so there is no second
      // write here that could succeed or fail on its own.
      // They arrived — the reminder is no longer needed.
      await reminders?.cancelFor(booking.id);
      await bookings.setReminderStatus(booking.id, ReminderStatus.done);
    }
    return started;
  }

  Future<void> cancel(String id) async {
    await bookings.setStatus(id, BookingStatus.cancelled);
    await reminders?.cancelFor(id);
    await bookings.setReminderStatus(id, ReminderStatus.done);
  }

  /// Turn the device reminder for a booking on or off.
  Future<void> setReminder(Booking booking, {required bool on}) async {
    if (on) {
      await reminders?.scheduleFor(booking);
      await bookings.setReminderStatus(booking.id, ReminderStatus.scheduled);
    } else {
      await reminders?.cancelFor(booking.id);
      await bookings.setReminderStatus(booking.id, ReminderStatus.off);
    }
  }
}

final bookingActionsProvider = Provider<BookingActions>((ref) => BookingActions(
      bookings: ref.watch(bookingRepositoryProvider),
      sessions: ref.watch(sessionRepositoryProvider),
      catalog: ref.watch(catalogRepositoryProvider),
      clock: ref.watch(clockProvider),
      reminders: ref.watch(bookingRemindersProvider),
      groups: ref.watch(groupSessionRepositoryProvider),
      boards: PadBoardLoader(
        catalog: ref.watch(catalogRepositoryProvider),
        sessions: ref.watch(sessionRepositoryProvider),
        groups: ref.watch(groupSessionRepositoryProvider),
        pads: ref.watch(controllerAllocationRepositoryProvider),
      ),
    ));
