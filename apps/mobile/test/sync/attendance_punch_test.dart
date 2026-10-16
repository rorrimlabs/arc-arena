/// Attendance end to end on one local Supabase stack: the owner sets the arena
/// location (settings key `attendance`), the staff login clocks in and out
/// through the floor app's real [SupabaseAttendanceRepository] (straight to
/// sync_push, server time, no outbox), and reads its own log back with the
/// punches' locations; a resent punch is recorded once; the owner sees the
/// entry; another arena's login sees nothing.
///
/// Skipped (not failed) outside tool/sync_it.sh.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/supabase_attendance_repository.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

void main() {
  final env = Platform.environment;
  final url = env['AO_SUPABASE_URL'];
  final key = env['AO_SUPABASE_ANON_KEY'];
  final password = env['AO_IT_PASSWORD'];
  final ownerEmail = env['AO_IT_OWNER_EMAIL'];
  final staffEmail = env['AO_IT_STAFF_EMAIL'];
  final outsiderEmail = env['AO_IT_OUTSIDER_EMAIL'];
  final arenaId = env['AO_IT_ARENA'];
  final skip = [url, key, password, ownerEmail, staffEmail, outsiderEmail, arenaId]
          .contains(null)
      ? 'runs only under tool/sync_it.sh'
      : null;

  Future<SupabaseClient> signIn(String email) async {
    final client = SupabaseClient(url!, key!,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await client.auth.signInWithPassword(email: email, password: password!);
    return client;
  }

  const inside = LocationReading.fix(
      lat: 12.9717, lng: 77.5946, accuracyM: 8, isMocked: false);
  const outside = LocationReading.fix(
      lat: 12.9760, lng: 77.5946, accuracyM: 8, isMocked: false);

  test('owner sets the location; staff clock in and out; logs read back',
      () async {
    final owner = await signIn(ownerEmail!);
    final staff = await signIn(staffEmail!);
    final outsider = await signIn(outsiderEmail!);
    addTearDown(() async {
      for (final c in [owner, staff, outsider]) {
        await c.auth.signOut();
        await c.dispose();
      }
    });

    // The owner saves the arena's attendance rules (Settings › Attendance).
    final saved = await SupabaseSyncTransport(owner).push(arenaId!, [
      (
        opId: const Uuid().v4(),
        kind: 'settings.save',
        payload: {
          'key': 'attendance',
          'json': {
            'geofence': {'lat': 12.9716, 'lng': 77.5946, 'radius_m': 100},
            'outside_rule': 'flag',
            'min_accuracy_m': 50,
            'mock_rule': 'block',
            'max_open_hours': 14,
          },
        },
      ),
    ], 'it-dashboard');
    expect(saved.single.status, 'applied', reason: '${saved.single.error}');

    var punched = 0;
    final repo = SupabaseAttendanceRepository(
      client: staff,
      transport: SupabaseSyncTransport(staff),
      arenaId: arenaId,
      userId: staff.auth.currentUser!.id,
      deviceId: () async => 'it-staff-phone',
      onPunched: () => punched++,
    );

    final rules = (await repo.rules()).valueOrNull!;
    expect(rules.geofence,
        const Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100));
    expect(rules.outsideRule, OutsideRule.flag);

    PunchCommand cmd(PunchKind kind, LocationReading at) => PunchCommand(
          punchId: const Uuid().v4(),
          kind: kind,
          reading: at,
          deviceAt: DateTime.utc(2000),
        );

    // Clock in at the arena.
    final clockIn = cmd(PunchKind.clockIn, inside);
    final first = (await repo.punch(clockIn)).valueOrNull!;
    expect(first.verdict, GeofenceVerdict.inside);
    expect(first.distanceM, 11);
    expect(first.needsReview, isFalse);
    expect(first.serverAt.year, greaterThan(2020),
        reason: 'the server stamps its own time, not the phone\'s (2000)');

    // The answer was "lost": the same command again replays, never doubles.
    final again = (await repo.punch(clockIn)).valueOrNull!;
    expect(again.entryId, first.entryId);
    expect(again.punchId, first.punchId);

    // A new clock-in while on the clock is refused, in words.
    final twice = (await repo.punch(cmd(PunchKind.clockIn, inside))).failureOrNull!;
    expect(twice.code, 'already_clocked_in');

    // Clock out from ~489 m away: accepted under flag, up for review.
    final out = (await repo.punch(cmd(PunchKind.clockOut, outside))).valueOrNull!;
    expect(out.entryId, first.entryId);
    expect(out.verdict, GeofenceVerdict.outside);
    expect(out.needsReview, isTrue);
    expect(punched, 3, reason: 'each recorded punch nudges the other devices');

    // A mock location is refused (mock_rule block).
    final mock = (await repo.punch(cmd(
            PunchKind.clockIn,
            const LocationReading.fix(
                lat: 12.9717, lng: 77.5946, accuracyM: 8, isMocked: true))))
        .failureOrNull!;
    expect(mock.code, 'mock_location');

    // The staff member's own log, with both punches and their evidence.
    final today = IstDate.fromUtc(first.serverAt);
    final mine = (await repo.myEntries(from: today.addDays(-1), to: today.addDays(1)))
        .valueOrNull!;
    final entry = mine.singleWhere((e) => e.id == first.entryId);
    expect(entry.isOpen, isFalse);
    expect(entry.workDate, today);
    expect(entry.flags, ['outside_out']);
    expect(entry.needsReview, isTrue);
    expect(entry.inPunch!.verdict, GeofenceVerdict.inside);
    expect(entry.inPunch!.deviceAt, DateTime.utc(2000));
    expect(entry.inPunch!.geofence!.radiusM, 100);
    expect(entry.outPunch!.distanceM, 489);
    expect(entry.outPunch!.lat, closeTo(12.9760, 1e-9));

    // The owner sees the entry; another arena's login sees nothing of it.
    final ownerView = await owner
        .from('attendance_entries')
        .select('id')
        .eq('id', first.entryId);
    expect(ownerView, hasLength(1));
    final outsiderView = await outsider
        .from('attendance_punches')
        .select('id')
        .eq('arena_id', arenaId);
    expect(outsiderView, isEmpty);
  }, skip: skip);
}
