/// A half-open time interval `[start, end)` in UTC.
///
/// Half-open semantics make "touching" intervals (one ends exactly when the
/// next begins) **not** overlap — which is what both the pricing band-split and
/// the availability checker need (spec §13 touching boundaries are allowed).
library;

import 'package:meta/meta.dart';

@immutable
class UtcInterval {
  UtcInterval(DateTime start, DateTime end)
      : start = start.toUtc(),
        end = end.toUtc(),
        assert(!end.toUtc().isBefore(start.toUtc()), 'end must be >= start');

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
  bool get isEmpty => !end.isAfter(start);

  /// True when the two intervals share more than a single boundary instant.
  bool overlaps(UtcInterval other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  /// The overlapping region, or null if they only touch or are disjoint.
  UtcInterval? intersection(UtcInterval other) {
    final s = start.isAfter(other.start) ? start : other.start;
    final e = end.isBefore(other.end) ? end : other.end;
    if (!e.isAfter(s)) return null;
    return UtcInterval(s, e);
  }

  bool contains(DateTime t) =>
      !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is UtcInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'UtcInterval($start .. $end)';
}
