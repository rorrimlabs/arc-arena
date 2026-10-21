/// Pure computation of a booking's reminder notifications (spec §23).
///
/// Given a booking, the resolved display names and a [ReminderPolicy], this
/// produces the exact notification payloads (id, fire time, title, body) to hand
/// to the device scheduler. No plugin, no I/O — so it is fully unit-tested, and
/// the platform layer stays a thin pass-through.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:meta/meta.dart';

/// What a notification is for, which decides how the phone rings it.
enum AlertKind {
  /// A booking about to start.
  booking,

  /// A session's 5- or 1-minute warning: rings once.
  warning,

  /// A session's time is up: an alarm, which can keep ringing until seen.
  timeUp,
}

@immutable
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    this.bookingId = '',
    this.sessionId,
    required this.fireAtUtc,
    required this.title,
    required this.body,
    this.kind = AlertKind.booking,
    this.enableVibration = true,
    this.playSound = true,
    this.ringUntilSeen = false,
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
  final AlertKind kind;
  final bool enableVibration;
  final bool playSound;

  /// Keeps sounding until opened or cleared (only ever on a [AlertKind.timeUp]).
  final bool ringUntilSeen;

  /// The same notification at another instant.
  ReminderPlan at(DateTime fireAtUtc) => ReminderPlan(
    id: id,
    bookingId: bookingId,
    sessionId: sessionId,
    fireAtUtc: fireAtUtc,
    title: title,
    body: body,
    kind: kind,
    enableVibration: enableVibration,
    playSound: playSound,
    ringUntilSeen: ringUntilSeen,
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
      other.kind == kind &&
      other.enableVibration == enableVibration &&
      other.playSound == playSound &&
      other.ringUntilSeen == ringUntilSeen;

  @override
  int get hashCode => Object.hash(
    id,
    bookingId,
    sessionId,
    fireAtUtc,
    title,
    body,
    kind,
    enableVibration,
    playSound,
    ringUntilSeen,
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
    plans.add(
      ReminderPlan(
        id: reminderId(booking.id, 0),
        bookingId: booking.id,
        fireAtUtc: leadAt,
        title: 'Booking in ${policy.leadMinutes} min',
        body: summary,
      ),
    );
  }

  if (policy.alsoAtStart && startUtc.isAfter(now)) {
    plans.add(
      ReminderPlan(
        id: reminderId(booking.id, 1),
        bookingId: booking.id,
        fireAtUtc: startUtc,
        title: 'Booking starting now',
        body: summary,
      ),
    );
  }

  return plans;
}

/// When session alert [slot] rings for a session due to end at
/// [scheduledEndAt]: slot 0 = 5 min before, slot 1 = 1 min before, slot 2 =
/// the end itself.
DateTime sessionAlertTime(DateTime scheduledEndAt, int slot) {
  final endUtc = scheduledEndAt.toUtc();
  return switch (slot) {
    0 => endUtc.subtract(const Duration(minutes: 5)),
    1 => endUtc.subtract(const Duration(minutes: 1)),
    _ => endUtc,
  };
}

/// Whether [settings] want session alert [slot] at all (the master switch,
/// then that slot's own).
bool sessionAlertWanted(NotificationSettings settings, int slot) =>
    settings.enabled &&
    switch (slot) {
      0 => settings.alert5Min,
      1 => settings.alert1Min,
      _ => settings.alertAtEnd,
    };

/// Builds local notification alerts for an active session (spec §23, timer alerts).
/// Slot 0: 5 minutes before scheduled end
/// Slot 1: 1 minute before scheduled end (spec: "1 min mune alert")
/// Slot 2: At scheduled end / Expired (spec: "സമയം കഴിഞ്ഞു") — the alarm, the
/// only one that may keep ringing until seen.
/// Nothing at all while [NotificationSettings.enabled] is off.
List<ReminderPlan> buildSessionAlerts({
  required String sessionId,
  required String titleName,
  required DateTime scheduledEndAt,
  required DateTime now,
  NotificationSettings settings = const NotificationSettings(),
}) {
  final plans = <ReminderPlan>[];
  final endLabel = IstTime.format12(scheduledEndAt.toUtc());

  /// [slot], if it is wanted and its time is still ahead.
  void add(int slot, String title, String body) {
    final at = sessionAlertTime(scheduledEndAt, slot);
    if (!sessionAlertWanted(settings, slot) || !at.isAfter(now)) return;
    final timeUp = slot == 2;
    plans.add(
      ReminderPlan(
        id: sessionAlertId(sessionId, slot),
        sessionId: sessionId,
        fireAtUtc: at,
        title: title,
        body: body,
        kind: timeUp ? AlertKind.timeUp : AlertKind.warning,
        enableVibration: settings.vibrationEnabled,
        playSound: settings.soundEnabled,
        ringUntilSeen: timeUp && settings.ringUntilSeen,
      ),
    );
  }

  // Slot 0: 5 min before
  add(
    0,
    '5 min remaining: $titleName',
    'Session ends at $endLabel. Prepare to extend or wrap up.',
  );
  // Slot 1: 1 min before (specifically required by user)
  add(
    1,
    '1 min remaining: $titleName',
    'Session ends in 1 minute ($endLabel)! Final reminder.',
  );
  // Slot 2: At scheduled end / Expired (specifically required by user)
  add(
    2,
    'Time Expired: $titleName',
    'Session time has ended ($endLabel). Ready for checkout.',
  );
  return plans;
}

/// The id of the settings screen's test alert: fixed, so a second tap
/// replaces the first instead of stacking two.
const int testAlertId = 0x7ffffff0;

/// A test alert [delay] from [now] that rings exactly like a session's "time
/// up" with [settings] (sound, vibration, ringing until seen) — so the person
/// can lock the phone and hear what the floor will hear.
ReminderPlan buildTestAlert({
  required DateTime now,
  required NotificationSettings settings,
  Duration delay = const Duration(seconds: 5),
}) => ReminderPlan(
  id: testAlertId,
  fireAtUtc: now.toUtc().add(delay),
  title: 'Test alert',
  body: 'This is how "time up" rings on this phone.',
  kind: AlertKind.timeUp,
  enableVibration: settings.vibrationEnabled,
  playSound: settings.soundEnabled,
  ringUntilSeen: settings.ringUntilSeen,
);
