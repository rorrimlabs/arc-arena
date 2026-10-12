/// Resource-availability rules (spec §12–§13). Pure Dart.
///
/// The center keeps at most one active session per resource, which also makes
/// RIFT's "PS5 and VR can't run at once" true for free: RIFT is a single
/// resource, so any active session on it blocks another regardless of activity.
///
/// Callers pass the current [Occupancy] list (active sessions + future bookings)
/// and the day's closing instant. When extending, the caller excludes the
/// session being extended from the occupancy list.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:meta/meta.dart';

/// Something occupying a resource for a stretch of time.
@immutable
class Occupancy {
  const Occupancy({
    required this.resourceId,
    required this.interval,
    required this.isBooking,
    this.label,
  });

  final String resourceId;
  final UtcInterval interval;

  /// True for a future booking, false for an active session.
  final bool isBooking;

  /// Human label for messages, e.g. a customer name.
  final String? label;
}

/// How far an active session can be extended, and what stops it going further.
@immutable
class ExtensionLimit {
  const ExtensionLimit({
    required this.max,
    required this.limitAt,
    required this.blockedByBooking,
    required this.unbounded,
  });

  /// The largest allowed extension beyond the current end (never negative).
  final Duration max;

  /// The instant that caps the extension (closing time or a booking start).
  final DateTime limitAt;

  /// True when the cap is a booking; false when it is closing time.
  final bool blockedByBooking;

  /// True when nothing caps the extension (open past close, no bookings).
  final bool unbounded;

  int get maxMinutes => max.inMinutes;
}

class AvailabilityService {
  const AvailabilityService();

  /// Whether a new session may occupy [resourceId] for [window].
  Result<void> canStart({
    required String resourceId,
    required String resourceName,
    required UtcInterval window,
    required Iterable<Occupancy> occupancies,
    required DateTime closeAt,
    required bool allowPastClose,
  }) {
    if (!allowPastClose && window.end.isAfter(closeAt)) {
      return Err(Failure(
        message: "Can't start past closing time (${IstTime.format12(closeAt)}).",
        fix: 'Shorten the session or pick a shorter duration.',
        code: 'past_close',
      ));
    }
    for (final occ in occupancies) {
      if (occ.resourceId == resourceId && occ.interval.overlaps(window)) {
        final who = occ.isBooking
            ? 'booked${occ.label == null ? '' : ' by ${occ.label}'}'
            : 'in use${occ.label == null ? '' : ' by ${occ.label}'}';
        return Err(Failure(
          message: '$resourceName is $who.',
          fix: 'Pick another station.',
          code: 'resource_busy',
        ));
      }
    }
    return const Ok(null);
  }

  /// The maximum extension available for an active session on [resourceId]
  /// whose current end is [currentEnd].
  ExtensionLimit maxExtension({
    required String resourceId,
    required DateTime currentEnd,
    required Iterable<Occupancy> occupancies,
    required DateTime closeAt,
    required bool allowPastClose,
  }) {
    DateTime? limit = allowPastClose ? null : closeAt;
    var blockedByBooking = false;

    for (final occ in occupancies) {
      if (occ.resourceId != resourceId) continue;
      final start = occ.interval.start;
      // A booking that begins at or after the current end caps the extension:
      // the current session may touch it (+0) but not extend into it.
      if (!start.isBefore(currentEnd)) {
        if (limit == null || start.isBefore(limit)) {
          limit = start;
          blockedByBooking = true;
        }
      }
    }

    if (limit == null) {
      return ExtensionLimit(
        max: Duration.zero,
        limitAt: currentEnd,
        blockedByBooking: false,
        unbounded: true,
      );
    }

    var max = limit.difference(currentEnd);
    if (max.isNegative) max = Duration.zero;
    return ExtensionLimit(
      max: max,
      limitAt: limit,
      blockedByBooking: blockedByBooking,
      unbounded: false,
    );
  }

  /// Whether an active session may be extended by [addedMinutes]. On success,
  /// returns the new end instant.
  Result<DateTime> canExtend({
    required String resourceId,
    required DateTime currentEnd,
    required int addedMinutes,
    required Iterable<Occupancy> occupancies,
    required DateTime closeAt,
    required bool allowPastClose,
  }) {
    final newEnd = currentEnd.add(Duration(minutes: addedMinutes));
    final limit = maxExtension(
      resourceId: resourceId,
      currentEnd: currentEnd,
      occupancies: occupancies,
      closeAt: closeAt,
      allowPastClose: allowPastClose,
    );

    if (limit.unbounded || !newEnd.isAfter(limit.limitAt)) {
      return Ok(newEnd);
    }

    final avail = limit.maxMinutes > 0
        ? 'Only +${limit.maxMinutes} min is available.'
        : 'No extension is available.';
    if (limit.blockedByBooking) {
      return Err(Failure(
        message: "Can't extend past ${IstTime.format12(limit.limitAt)}. "
            'This station is booked.',
        fix: avail,
        code: 'extend_booking',
      ));
    }
    return Err(Failure(
      message: "Can't extend past closing time (${IstTime.format12(limit.limitAt)}).",
      fix: avail,
      code: 'extend_past_close',
    ));
  }
}
