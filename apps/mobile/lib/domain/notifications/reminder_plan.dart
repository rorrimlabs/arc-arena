/// Pure computation of a booking's reminder notifications (spec §23).
///
/// Given a booking, the resolved display names and a [ReminderPolicy], this
/// produces the exact notification payloads (id, fire time, title, body) to hand
/// to the device scheduler. No plugin, no I/O — so it is fully unit-tested, and
/// the platform layer stays a thin pass-through.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:meta/meta.dart';

@immutable
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    this.bookingId = '',
    this.sessionId,
    required this.fireAtUtc,
    required this.title,
    required this.body,
    this.channelId,
    this.enableVibration = true,
    this.playSound = true,
  });

  /// Stable notification id (deterministic from the booking/session id + slot),
  /// so the same booking or session always reschedules/cancels the same
  /// notification — no duplicates after an app restart.
  final int id;
  final String bookingId;
  final String? sessionId;
  final DateTime fireAtUtc;
  final String title;
  final String body;
  final String? channelId;
  final bool enableVibration;
  final bool playSound;

  /// The same notification at another instant.
  ReminderPlan at(DateTime fireAtUtc) => ReminderPlan(
        id: id,
        bookingId: bookingId,
        sessionId: sessionId,
        fireAtUtc: fireAtUtc,
        title: title,
        body: body,
        channelId: channelId,
        enableVibration: enableVibration,
        playSound: playSound,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderPlan &&
      other.id == id &&
      other.bookingId == bookingId &&
      other.sessionId == sessionId &&
      other.fireAtUtc == fireAtUtc &&
      other.title == title &&
      other.body == body &&
      other.enableVibration == enableVibration &&
      other.playSound == playSound;

  @override
  int get hashCode => Object.hash(
        id,
        bookingId,
        sessionId,
        fireAtUtc,
        title,
        body,
        enableVibration,
        playSound,
      );

  @override
  String toString() =>
      'ReminderPlan(id: $id, booking: $bookingId, sess: $sessionId, at: $fireAtUtc, "$body")';
}

/// A stable, positive 31-bit id from the booking id + a slot (0 = lead reminder,
/// 1 = at-start reminder). Uses FNV-1a so it is identical across app restarts and
/// platforms (unlike `String.hashCode`), which is what makes cancellation and
/// de-duplication reliable.
int reminderId(String bookingId, int slot) {
  var hash = 0x811c9dc5;
  for (final unit in bookingId.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  hash = (hash ^ (slot * 0x9e3779b1)) & 0xffffffff;
  return hash & 0x7fffffff;
}

/// A stable, positive 31-bit id for a session alert (slot 0 = 5 min before,
/// slot 1 = 1 min before, slot 2 = at end / expired).
int sessionAlertId(String sessionId, int slot) {
  var hash = 0x811c9dc5;
  for (final unit in 'sess:$sessionId'.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  hash = (hash ^ (slot * 0x9e3779b1)) & 0xffffffff;
  return hash & 0x7fffffff;
}

/// Builds the reminder(s) for [booking]. Returns only reminders whose fire time
/// is still in the future relative to [now] — a booking created 10 minutes
/// before it starts simply schedules nothing (or only the at-start one).
List<ReminderPlan> buildBookingReminders({
  required Booking booking,
  required String customerName,
  required String activityLabel,
  String? gameName,
  String? resourceName,
  ReminderPolicy policy = ReminderPolicy.defaults,
  required DateTime now,
}) {
  final startUtc = booking.scheduledStart.toUtc();
  final startLabel = IstTime.format12(startUtc);
  final summary = [
    customerName,
    activityLabel,
    if (gameName != null && gameName.isNotEmpty) gameName,
    if (resourceName != null && resourceName.isNotEmpty) resourceName,
    startLabel,
  ].join(' — ');

  final plans = <ReminderPlan>[];

  final leadAt = startUtc.subtract(Duration(minutes: policy.leadMinutes));
  if (leadAt.isAfter(now)) {
    plans.add(ReminderPlan(
      id: reminderId(booking.id, 0),
      bookingId: booking.id,
      fireAtUtc: leadAt,
      title: 'Booking in ${policy.leadMinutes} min',
      body: summary,
    ));
  }

  if (policy.alsoAtStart && startUtc.isAfter(now)) {
    plans.add(ReminderPlan(
      id: reminderId(booking.id, 1),
      bookingId: booking.id,
      fireAtUtc: startUtc,
      title: 'Booking starting now',
      body: summary,
    ));
  }

  return plans;
}

/// Builds local notification alerts for an active session (spec §23, timer alerts).
/// Slot 0: 5 minutes before scheduled end ("Ending soon (5m)")
/// Slot 1: 1 minute before scheduled end ("Ending soon (1m)")
/// Slot 2: At scheduled end / Expired ("Session time completed")
List<ReminderPlan> buildSessionAlerts({
  required String sessionId,
  required String titleName,
  String? customerName,
  required DateTime scheduledEndAt,
  required DateTime now,
  bool vibrationEnabled = true,
  bool soundEnabled = true,
  bool alert5Min = true,
  bool alert1Min = true,
  bool alertAtEnd = true,
}) {
  final plans = <ReminderPlan>[];
  final endUtc = scheduledEndAt.toUtc();
  final endLabel = IstTime.format12(endUtc);
  final custPrefix = (customerName != null && customerName.isNotEmpty)
      ? '$customerName • '
      : '';

  // Slot 0: 5 min before
  if (alert5Min) {
    final fiveMinAt = endUtc.subtract(const Duration(minutes: 5));
    if (fiveMinAt.isAfter(now)) {
      plans.add(ReminderPlan(
        id: sessionAlertId(sessionId, 0),
        sessionId: sessionId,
        fireAtUtc: fiveMinAt,
        title: '$titleName — Ending soon (5m)',
        body: '${custPrefix}Session ends at $endLabel. Prepare to extend or wrap up.',
        enableVibration: vibrationEnabled,
        playSound: soundEnabled,
      ));
    }
  }

  // Slot 1: 1 min before (specifically required by user)
  if (alert1Min) {
    final oneMinAt = endUtc.subtract(const Duration(minutes: 1));
    if (oneMinAt.isAfter(now)) {
      plans.add(ReminderPlan(
        id: sessionAlertId(sessionId, 1),
        sessionId: sessionId,
        fireAtUtc: oneMinAt,
        title: '$titleName — Ending soon (1m)',
        body: '${custPrefix}Session ends in 1 minute ($endLabel)! Final reminder.',
        enableVibration: vibrationEnabled,
        playSound: soundEnabled,
      ));
    }
  }

  // Slot 2: At scheduled end / Expired (specifically required by user)
  if (alertAtEnd) {
    if (endUtc.isAfter(now)) {
      plans.add(ReminderPlan(
        id: sessionAlertId(sessionId, 2),
        sessionId: sessionId,
        fireAtUtc: endUtc,
        title: '$titleName — Session time completed',
        body: '${custPrefix}Session time has ended ($endLabel). Ready for checkout.',
        enableVibration: vibrationEnabled,
        playSound: soundEnabled,
      ));
    }
  }

  return plans;
}
