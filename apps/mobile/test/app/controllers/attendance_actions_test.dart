import 'package:arena_ops/app/controllers/attendance_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance.dart';
import '../../support/pricing_fixtures.dart' show ist;

void main() {
  final now = ist(2026, 10, 15, 11, 0);
  late FakeAttendanceRepository repo;
  late FakeLocationProbe probe;

  // A floor staffer with no attendance permission: everyone may clock in.
  const staff = AppUser(id: 'u2', name: 'Ravi', perms: {Permission.start});

  AttendanceActions actions({AppUser? user = staff, Clock? clock}) => AttendanceActions(
        attendance: repo,
        location: probe,
        clock: clock ?? FakeClock(now),
        guard: PermissionGuard(user),
      );

  setUp(() {
    repo = FakeAttendanceRepository(serverNow: () => now);
    probe = FakeLocationProbe();
  });

  test('any active member clocks in, no permission needed', () async {
    final a = actions();
    final res = await a.send(a.prepare(PunchKind.clockIn, await a.readLocation()));
    expect(res.isOk, isTrue);
    expect(repo.sent.single.kind, PunchKind.clockIn);
    expect(probe.reads, 1);
  });

  test('nobody signed in, or a turned-off account: refused before sending', () async {
    final out = actions(user: null);
    expect((await out.send(out.prepare(PunchKind.clockIn, FakeLocationProbe.inside)))
        .failureOrNull!.code, 'not_signed_in');
    final off = actions(user: const AppUser(id: 'u9', name: 'Gone', perms: {}, active: false));
    expect((await off.send(off.prepare(PunchKind.clockIn, FakeLocationProbe.inside)))
        .failureOrNull!.code, 'account_inactive');
    expect(repo.sent, isEmpty);
  });

  test('every prepared punch has its own id; resending keeps it', () async {
    final a = actions();
    final first = a.prepare(PunchKind.clockIn, FakeLocationProbe.inside);
    final second = a.prepare(PunchKind.clockIn, FakeLocationProbe.inside);
    expect(first.punchId, isNot(second.punchId));
    repo.nextFailure = const Failure(message: 'offline', code: 'offline');
    expect((await a.send(first)).isOk, isFalse);
    expect((await a.send(first)).isOk, isTrue);
    expect(repo.sent.map((c) => c.punchId), [first.punchId, first.punchId]);
  });

  test('device_at is the phone\'s own clock, not the server-corrected one', () {
    // The phone runs 10 minutes slow; the app's clock is corrected forward.
    final clock = OffsetClock(FakeClock(now), const Duration(minutes: 10));
    final cmd = actions(clock: clock).prepare(PunchKind.clockIn, FakeLocationProbe.inside);
    expect(cmd.deviceAt, now);
    expect(clock.now(), now.add(const Duration(minutes: 10)));
  });

  test('failures pass through unchanged', () async {
    const f = Failure(message: 'outside', fix: 'go in', code: 'outside_geofence');
    repo.nextFailure = f;
    final a = actions();
    expect((await a.send(a.prepare(PunchKind.clockIn, FakeLocationProbe.outside)))
        .failureOrNull, f);
  });
}
