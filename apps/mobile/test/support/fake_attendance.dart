import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';

/// Plays the server for attendance: keeps entries in memory, opens one on a
/// clock-in and closes it on a clock-out, or answers with [nextFailure].
class FakeAttendanceRepository implements AttendanceRepository {
  FakeAttendanceRepository({
    this.rulesValue = const AttendanceRules(
        geofence: Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100)),
    List<AttendanceEntry>? entries,
    required this.serverNow,
  }) : entries = entries ?? [];

  AttendanceRules rulesValue;
  final List<AttendanceEntry> entries;
  DateTime Function() serverNow;

  /// Answer the next punch with this instead of recording it.
  Failure? nextFailure;
  final sent = <PunchCommand>[];
  Failure? loadFailure;

  /// What the server says about each day (attendance_days); none = no rows.
  final days = <AttendanceDay>[];

  @override
  Future<Result<AttendanceRules>> rules() async => Ok(rulesValue);

  @override
  Future<Result<List<AttendanceEntry>>> myEntries({
    required IstDate from,
    required IstDate to,
  }) async {
    final f = loadFailure;
    if (f != null) return Err(f);
    return Ok([
      for (final e in entries)
        if (e.workDate.compareTo(from) >= 0 && e.workDate.compareTo(to) <= 0) e,
    ]..sort((a, b) => b.inAt.compareTo(a.inAt)));
  }

  @override
  Future<Result<List<AttendanceDay>>> myDays({
    required IstDate from,
    required IstDate to,
  }) async {
    final f = loadFailure;
    if (f != null) return Err(f);
    return Ok([
      for (final d in days)
        if (d.day.compareTo(from) >= 0 && d.day.compareTo(to) <= 0) d,
    ]..sort((a, b) => a.day.compareTo(b.day)));
  }

  @override
  Future<Result<PunchOutcome>> punch(PunchCommand cmd) async {
    sent.add(cmd);
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      return Err(f);
    }
    final at = serverNow();
    final preview = previewPunch(cmd.reading, rulesValue);
    final punch = AttendancePunch(
      id: cmd.punchId,
      kind: cmd.kind,
      serverAt: at,
      deviceAt: cmd.deviceAt,
      lat: cmd.reading.lat,
      lng: cmd.reading.lng,
      accuracyM: cmd.reading.accuracyM,
      isMocked: cmd.reading.isMocked,
      locationStatus: cmd.reading.status.wire,
      distanceM: preview.distanceM,
      verdict: preview.verdict,
      geofence: rulesValue.geofence,
    );
    final review = preview.willBeFlagged ? 'pending' : 'none';
    String entryId;
    if (cmd.kind == PunchKind.clockIn) {
      entryId = 'entry-${entries.length + 1}';
      entries.add(AttendanceEntry(
        id: entryId,
        workDate: IstDate.fromUtc(at),
        inAt: at,
        inPunch: punch,
        review: review,
      ));
    } else {
      final i = entries.indexWhere((e) => e.isOpen);
      entryId = entries[i].id;
      entries[i] = entries[i].copyWith(
        outAt: at,
        outSource: 'punch',
        outPunch: punch,
        review: review == 'pending' ? 'pending' : entries[i].review,
      );
    }
    return Ok(PunchOutcome(
      punchId: cmd.punchId,
      entryId: entryId,
      kind: cmd.kind,
      serverAt: at,
      verdict: preview.verdict,
      distanceM: preview.distanceM,
      review: review,
    ));
  }
}

/// Returns [next] for every reading.
class FakeLocationProbe implements LocationProbe, LocationSettingsOpener {
  FakeLocationProbe([this.next = inside]);

  static const inside = LocationReading.fix(
      lat: 12.9717, lng: 77.5946, accuracyM: 8, isMocked: false);
  static const outside = LocationReading.fix(
      lat: 12.9760, lng: 77.5946, accuracyM: 8, isMocked: false);

  LocationReading next;
  int reads = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<LocationReading> read() async {
    reads++;
    return next;
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}
