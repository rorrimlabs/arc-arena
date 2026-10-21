/// A stretch of work (clock-in to clock-out) and the punches behind it, as the
/// server recorded them. All times are the server's.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'attendance_entry.freezed.dart';

enum PunchKind {
  clockIn('in'),
  clockOut('out');

  const PunchKind(this.wire);
  final String wire;
}

/// One clock-in or clock-out, with the evidence taken at that moment.
@freezed
abstract class AttendancePunch with _$AttendancePunch {
  const factory AttendancePunch({
    required String id,
    required PunchKind kind,

    /// When the server received it — the time that counts.
    required DateTime serverAt,

    /// What the phone's clock said (evidence only).
    DateTime? deviceAt,
    double? lat,
    double? lng,
    double? accuracyM,
    bool? isMocked,

    /// `attendance_punches.location_status` (ok, denied, gps_off, …).
    required String locationStatus,
    int? distanceM,
    required GeofenceVerdict verdict,

    /// The geofence in force when the punch was judged.
    Geofence? geofence,
    @Default(<String>[]) List<String> flags,
  }) = _AttendancePunch;
}

@freezed
abstract class AttendanceEntry with _$AttendanceEntry {
  const AttendanceEntry._();

  const factory AttendanceEntry({
    required String id,

    /// The IST day the clock-in fell on (a shift past midnight stays there).
    required IstDate workDate,
    required DateTime inAt,

    /// Null while the person is on the clock.
    DateTime? outAt,

    /// punch, auto (closed automatically) or manual; null while open.
    String? outSource,
    @Default(<String>[]) List<String> flags,

    /// none, pending, accepted or corrected.
    @Default('none') String review,
    AttendancePunch? inPunch,
    AttendancePunch? outPunch,
  }) = _AttendanceEntry;

  bool get isOpen => outAt == null;
  bool get closedAutomatically => outSource == 'auto';
  bool get needsReview => review == 'pending';

  /// Clocked time: to the clock-out, or to [now] while still open.
  Duration workedAt(DateTime now) {
    final end = outAt ?? now;
    return end.isBefore(inAt) ? Duration.zero : end.difference(inAt);
  }
}

/// The person's open stretch, if any (newest first in [entries] or not).
AttendanceEntry? openEntryOf(Iterable<AttendanceEntry> entries) =>
    entries.where((e) => e.isOpen).fold<AttendanceEntry?>(
        null, (a, e) => a == null || e.inAt.isAfter(a.inAt) ? e : a);

/// Clocked time on [day] (by work date) as of [now], open stretch included.
/// Raw clocked time: breaks and rounding come with shifts (a later phase).
Duration clockedOn(IstDate day, Iterable<AttendanceEntry> entries, DateTime now) =>
    entries
        .where((e) => e.workDate == day)
        .fold(Duration.zero, (sum, e) => sum + e.workedAt(now));
