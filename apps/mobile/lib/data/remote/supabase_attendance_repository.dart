/// [AttendanceRepository] straight against the server.
///
/// Attendance is not part of the device database or the sync outbox: a punch
/// goes to sync_push at once (the server stamps it with its own time), and the
/// log is read online through RLS (a member sees their own rows). The punch id
/// doubles as the op id, so resending a command whose answer was lost replays
/// the first answer instead of recording a second punch.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';
import 'package:arena_ops/data/remote/online_calls.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAttendanceRepository implements AttendanceRepository {
  SupabaseAttendanceRepository({
    required this._client,
    required this._transport,
    required this.arenaId,
    required this.userId,
    required this.deviceId,
    this.onPunched,
    this.timeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;
  final SyncTransport _transport;
  final String arenaId;
  final String userId;
  final Future<String> Function() deviceId;

  /// Called after the server recorded a punch (to nudge other devices).
  final void Function()? onPunched;
  final Duration timeout;

  String? _staffId;

  static const _punchCols = 'id, kind, server_at, device_at, lat, lng, '
      'accuracy_m, is_mocked, location_status, distance_m, geofence, '
      'geofence_snapshot, flags';

  @override
  Future<Result<AttendanceRules>> rules() => _read(() async {
        final row = await _client
            .from('settings')
            .select('json')
            .eq('arena_id', arenaId)
            .eq('key', 'attendance')
            .maybeSingle()
            .timeout(timeout);
        final json = row?['json'];
        return AttendanceRules.fromJson(
            json is Map ? Map<String, dynamic>.from(json) : null);
      });

  @override
  Future<Result<List<AttendanceEntry>>> myEntries({
    required IstDate from,
    required IstDate to,
  }) =>
      _read(() async {
        final staffId = await _myStaffId();
        final rows = await _client
            .from('attendance_entries')
            .select('id, work_date, in_at, out_at, out_source, flags, review, '
                'in_punch:attendance_punches!attendance_entries_in_punch_id_fkey($_punchCols), '
                'out_punch:attendance_punches!attendance_entries_out_punch_id_fkey($_punchCols)')
            .eq('arena_id', arenaId)
            .eq('staff_id', staffId)
            .eq('status', 'active')
            .gte('work_date', from.iso)
            .lte('work_date', to.iso)
            .order('in_at', ascending: false)
            .timeout(timeout);
        return [for (final r in rows) entryFromRow(r)];
      });

  @override
  Future<Result<PunchOutcome>> punch(PunchCommand cmd) async {
    final device = await deviceId();
    final res = await pushNow(
      _transport,
      arenaId: arenaId,
      deviceId: device,
      opId: cmd.punchId,
      kind: 'attendance.punch',
      payload: punchPayload(cmd, device),
      rejected: AttendanceFailures.rejected,
    );
    if (res case Ok(value: final result)) {
      onPunched?.call();
      return Ok(outcomeFromResult(result));
    }
    return Err(res.failureOrNull!);
  }

  @override
  Future<Result<List<AttendanceDay>>> myDays({
    required IstDate from,
    required IstDate to,
  }) =>
      _read(() async {
        final rows = await _client.rpc('attendance_days', params: {
          'p_arena': arenaId,
          'p_from': from.iso,
          'p_to': to.iso,
          'p_staff': await _myStaffId(),
        }).timeout(timeout);
        return [
          for (final r in (rows as List? ?? const []))
            AttendanceDay.fromJson(Map<String, dynamic>.from(r as Map)),
        ];
      });

  Future<String> _myStaffId() async {
    final cached = _staffId;
    if (cached != null) return cached;
    final row = await _client
        .from('staff_profiles')
        .select('id')
        .eq('arena_id', arenaId)
        .eq('user_id', userId)
        .single()
        .timeout(timeout);
    return _staffId = row['id'] as String;
  }

  Future<Result<T>> _read<T>(Future<T> Function() body) =>
      onlineRead(_client, body);
}

/// The `attendance.punch` payload (op_attendance_punch).
@visibleForTesting
Map<String, dynamic> punchPayload(PunchCommand cmd, String deviceId) => {
      'punch_id': cmd.punchId,
      'kind': cmd.kind.wire,
      'device_id': deviceId,
      'device_at': cmd.deviceAt.toUtc().toIso8601String(),
      'location': cmd.reading.toWire(),
    };

@visibleForTesting
PunchOutcome outcomeFromResult(Map<String, dynamic> j) => PunchOutcome(
      punchId: j['punch_id'] as String,
      entryId: j['entry_id'] as String,
      kind: j['kind'] == 'out' ? PunchKind.clockOut : PunchKind.clockIn,
      serverAt: DateTime.parse(j['server_at'] as String).toUtc(),
      verdict: GeofenceVerdict.fromWire(j['geofence'] as String?),
      distanceM: (j['distance_m'] as num?)?.toInt(),
      flags: [for (final f in (j['flags'] as List? ?? const [])) f as String],
      review: j['review'] as String? ?? 'none',
      autoClosedEntryId: j['auto_closed_entry_id'] as String?,
    );

@visibleForTesting
AttendanceEntry entryFromRow(Map<String, dynamic> r) => AttendanceEntry(
      id: r['id'] as String,
      workDate: IstDate.parse(r['work_date'] as String),
      inAt: DateTime.parse(r['in_at'] as String).toUtc(),
      outAt: r['out_at'] == null
          ? null
          : DateTime.parse(r['out_at'] as String).toUtc(),
      outSource: r['out_source'] as String?,
      flags: [for (final f in (r['flags'] as List? ?? const [])) f as String],
      review: r['review'] as String? ?? 'none',
      inPunch: r['in_punch'] is Map
          ? punchFromRow(Map<String, dynamic>.from(r['in_punch'] as Map))
          : null,
      outPunch: r['out_punch'] is Map
          ? punchFromRow(Map<String, dynamic>.from(r['out_punch'] as Map))
          : null,
    );

@visibleForTesting
AttendancePunch punchFromRow(Map<String, dynamic> r) => AttendancePunch(
      id: r['id'] as String,
      kind: r['kind'] == 'out' ? PunchKind.clockOut : PunchKind.clockIn,
      serverAt: DateTime.parse(r['server_at'] as String).toUtc(),
      deviceAt: r['device_at'] == null
          ? null
          : DateTime.parse(r['device_at'] as String).toUtc(),
      lat: (r['lat'] as num?)?.toDouble(),
      lng: (r['lng'] as num?)?.toDouble(),
      accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
      isMocked: r['is_mocked'] as bool?,
      locationStatus: r['location_status'] as String? ?? 'unavailable',
      distanceM: (r['distance_m'] as num?)?.toInt(),
      verdict: GeofenceVerdict.fromWire(r['geofence'] as String?),
      geofence: Geofence.fromJson(
          (r['geofence_snapshot'] as Map?)?['geofence']),
      flags: [for (final f in (r['flags'] as List? ?? const [])) f as String],
    );
