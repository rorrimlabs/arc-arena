/// Derives elapsed / remaining / overtime for a session purely from its
/// timestamps and the current time (spec §7). There is NO counter: given the
/// same timestamps and the same `now`, the result is identical — so the timer
/// rebuilds correctly after the app is closed and reopened.
library;

import 'package:meta/meta.dart';

/// The three visual states shown on the floor (spec §14, §24).
enum SessionVisualState { normal, warning, overtime }

@immutable
class SessionTimer {
  const SessionTimer({
    required this.startedAt,
    required this.scheduledEndAt,
    this.actualEndedAt,
    this.warnThreshold = const Duration(minutes: 5),
  });

  final DateTime startedAt;
  final DateTime scheduledEndAt;

  /// Set once the session has ended; freezes elapsed at the real end.
  final DateTime? actualEndedAt;

  /// How long before scheduled end the card turns amber.
  final Duration warnThreshold;

  /// Time played so far (frozen at [actualEndedAt] once ended).
  Duration elapsed(DateTime now) =>
      (actualEndedAt ?? now).difference(startedAt);

  /// Time left until scheduled end. Zero once past it (see [overtime]).
  Duration remaining(DateTime now) {
    final end = actualEndedAt ?? now;
    final left = scheduledEndAt.difference(end);
    return left.isNegative ? Duration.zero : left;
  }

  bool isOvertime(DateTime now) {
    if (actualEndedAt != null) return false;
    return now.isAfter(scheduledEndAt);
  }

  /// How far past scheduled end (zero when not overtime).
  Duration overtime(DateTime now) {
    if (!isOvertime(now)) return Duration.zero;
    return now.difference(scheduledEndAt);
  }

  SessionVisualState state(DateTime now) {
    if (isOvertime(now)) return SessionVisualState.overtime;
    if (remaining(now) <= warnThreshold) return SessionVisualState.warning;
    return SessionVisualState.normal;
  }
}
