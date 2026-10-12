/// How far ahead of a booking the staff want to be reminded (spec §23).
///
/// Configurable with a safe default (30 minutes before). Kept as a value object
/// so the owner-config screen can change it later with no code redesign — see
/// `docs/OWNER_CONFIRMATION.md`.
library;

import 'package:meta/meta.dart';

@immutable
class ReminderPolicy {
  const ReminderPolicy({
    this.leadMinutes = 30,
    this.alsoAtStart = false,
  });

  /// Minutes before the booking start to fire the reminder.
  final int leadMinutes;

  /// Also fire a second reminder exactly at the booking start time.
  final bool alsoAtStart;

  static const ReminderPolicy defaults = ReminderPolicy();
}
