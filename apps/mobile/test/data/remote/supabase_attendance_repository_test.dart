import 'dart:io';

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/supabase_attendance_repository.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/scripted_transport.dart';

void main() {
  late ScriptedTransport transport;
  late SupabaseAttendanceRepository repo;
  var punched = 0;

  final cmd = PunchCommand(
    punchId: '11111111-1111-4111-8111-111111111111',
    kind: PunchKind.clockIn,
    reading: const LocationReading.fix(
        lat: 12.9717, lng: 77.5946, accuracyM: 8, isMocked: false),
    deviceAt: DateTime.utc(2026, 10, 15, 5, 32),
  );

  setUp(() {
    transport = ScriptedTransport();
    punched = 0;
    repo = SupabaseAttendanceRepository(
      // Never called by punch(): writes go through the transport.
      client: SupabaseClient('http://127.0.0.1:9', 'test-key'),
      transport: transport,
      arenaId: 'arena-1',
      userId: 'user-1',
      deviceId: () async => 'device-1',
      onPunched: () => punched++,
    );
  });

  test('a punch is one attendance.punch op whose id is the punch id', () async {
    transport.onPush = (op) => OpResult(opId: op.opId, status: 'applied', result: {
          'punch_id': cmd.punchId,
          'entry_id': 'e1',
          'kind': 'in',
          'server_at': '2026-10-15T05:32:10.5+00:00',
          'geofence': 'inside',
          'distance_m': 11,
          'flags': <String>[],
          'review': 'none',
          'auto_closed_entry_id': null,
        });
    final res = await repo.punch(cmd);
    final op = transport.pushed.single;
    expect(op.opId, cmd.punchId, reason: 'resending the command replays, never doubles');
    expect(op.kind, 'attendance.punch');
    expect(op.payload, {
      'punch_id': cmd.punchId,
      'kind': 'in',
      'device_id': 'device-1',
      'device_at': '2026-10-15T05:32:00.000Z',
      'location': {
        'status': 'ok',
        'lat': 12.9717,
        'lng': 77.5946,
        'accuracy_m': 8.0,
        'is_mocked': false,
      },
    });
    final outcome = res.valueOrNull!;
    expect(outcome.entryId, 'e1');
    expect(outcome.verdict, GeofenceVerdict.inside);
    expect(outcome.distanceM, 11);
    expect(outcome.serverAt, DateTime.utc(2026, 10, 15, 5, 32, 10, 500));
    expect(punched, 1, reason: 'other devices are nudged');
  });

  test('a refusal becomes the failure for its code, with the server detail', () async {
    transport.onPush = (op) => OpResult(
        opId: op.opId,
        status: 'rejected',
        error: 'outside_geofence',
        detail: '489 m from the arena; the limit is 100 m');
    final f = (await repo.punch(cmd)).failureOrNull!;
    expect(f.code, 'outside_geofence');
    expect(f.message, contains('489 m from the arena'));
    expect(f.fix, isNotNull);
    expect(punched, 0);
  });

  test('every server code has its own words', () async {
    for (final code in [
      'already_clocked_in',
      'not_clocked_in',
      'location_required',
      'mock_location',
      'not_found',
      'duplicate',
      'invalid_payload',
    ]) {
      transport.onPush =
          (op) => OpResult(opId: op.opId, status: 'rejected', error: code);
      final f = (await repo.punch(cmd)).failureOrNull!;
      expect(f.code, code);
      expect(f.message, isNot(contains(code)), reason: '$code reads as words');
      expect(f.fix, isNotNull, reason: '$code says what to do');
    }
  });

  test('no connection: offline, nothing recorded locally', () async {
    transport.pushThrows = SyncOfflineException(const SocketException('down'));
    expect((await repo.punch(cmd)).failureOrNull!.code, 'offline');
  });

  test('access turned off / signed out', () async {
    transport.pushThrows = SyncAuthException('gone', revoked: true);
    expect((await repo.punch(cmd)).failureOrNull!.code, 'forbidden');
    transport.pushThrows = SyncAuthException('expired');
    expect((await repo.punch(cmd)).failureOrNull!.code, 'not_signed_in');
  });

  test('a busy server asks for the same punch again', () async {
    transport.onPush = (op) => OpResult(opId: op.opId, status: 'retry', error: '40001');
    expect((await repo.punch(cmd)).failureOrNull!.code, 'retry');
  });

  test('entryFromRow reads an entry with both punches', () {
    final e = entryFromRow({
      'id': 'e1',
      'work_date': '2026-10-15',
      'in_at': '2026-10-15T05:30:00+00:00',
      'out_at': '2026-10-15T14:30:00+00:00',
      'out_source': 'punch',
      'flags': ['outside_out'],
      'review': 'pending',
      'in_punch': {
        'id': 'p1',
        'kind': 'in',
        'server_at': '2026-10-15T05:30:00+00:00',
        'device_at': '2026-10-15T05:29:58+00:00',
        'lat': 12.9717,
        'lng': 77.5946,
        'accuracy_m': 8.0,
        'is_mocked': false,
        'location_status': 'ok',
        'distance_m': 11,
        'geofence': 'inside',
        'geofence_snapshot': {
          'geofence': {'lat': 12.9716, 'lng': 77.5946, 'radius_m': 100},
          'outside_rule': 'flag',
        },
        'flags': <String>[],
      },
      'out_punch': {
        'id': 'p2',
        'kind': 'out',
        'server_at': '2026-10-15T14:30:00+00:00',
        'lat': null,
        'lng': null,
        'accuracy_m': null,
        'is_mocked': null,
        'location_status': 'gps_off',
        'distance_m': null,
        'geofence': 'unknown',
        'geofence_snapshot': {'geofence': null},
        'flags': ['unknown'],
      },
    });
    expect(e.workDate.iso, '2026-10-15');
    expect(e.isOpen, isFalse);
    expect(e.needsReview, isTrue);
    expect(e.inPunch!.verdict, GeofenceVerdict.inside);
    expect(e.inPunch!.geofence, const Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100));
    expect(e.outPunch!.kind, PunchKind.clockOut);
    expect(e.outPunch!.lat, isNull);
    expect(e.outPunch!.geofence, isNull);
    expect(e.workedAt(DateTime.utc(2030)), const Duration(hours: 9));
  });

  test('an open entry without an out punch', () {
    final e = entryFromRow({
      'id': 'e2',
      'work_date': '2026-10-15',
      'in_at': '2026-10-15T05:30:00Z',
      'out_at': null,
      'out_source': null,
      'flags': <String>[],
      'review': 'none',
      'in_punch': null,
      'out_punch': null,
    });
    expect(e.isOpen, isTrue);
    expect(e.inPunch, isNull);
  });

  test('without a session, reads say sign in again (never call as anon)', () async {
    final r = await repo.myEntries(
        from: const IstDate(2026, 10, 1), to: const IstDate(2026, 10, 15));
    expect(r, isA<Err<List<AttendanceEntry>>>());
    expect(r.failureOrNull!.code, 'not_signed_in');
    expect((await repo.rules()).failureOrNull!.code, 'not_signed_in');
  });
}
