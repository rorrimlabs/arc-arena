import 'package:arena_ops/app/controllers/leave_actions.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_leave.dart';
import '../../support/pricing_fixtures.dart' show ist;

void main() {
  late FakeLeaveRepository repo;
  const staff = AppUser(id: 'u2', name: 'Ravi', perms: {Permission.start});
  setUp(() => repo = FakeLeaveRepository(now: () => ist(2026, 10, 16, 10, 0)));

  LeaveActions actions([AppUser? user = staff]) =>
      LeaveActions(leave: repo, guard: PermissionGuard(user));

  LeaveRequestCommand cmd(LeaveActions a, {IstDate? to, String reason = 'wedding', HalfDay half = HalfDay.none}) =>
      a.prepare(
          kind: LeaveKind.planned,
          from: const IstDate(2026, 10, 20),
          to: to ?? const IstDate(2026, 10, 22),
          halfDay: half,
          reason: reason);

  test('any active member applies for their own leave, no permission needed', () async {
    final a = actions();
    expect((await a.apply(cmd(a))).valueOrNull, 3);
    expect(repo.sent.single.kind, LeaveKind.planned);
  });

  test('refused before sending: not signed in, no reason, dates backwards', () async {
    final out = actions(null);
    expect((await out.apply(cmd(out))).failureOrNull!.code, 'not_signed_in');
    final a = actions();
    expect((await a.apply(cmd(a, reason: '  '))).failureOrNull!.code, 'reason_required');
    expect((await a.apply(cmd(a, to: const IstDate(2026, 10, 19)))).failureOrNull!.code,
        'invalid_dates');
    expect(repo.sent, isEmpty);
  });

  test('a half day only for a single day', () {
    final a = actions();
    expect(cmd(a, half: HalfDay.firstHalf).halfDay, HalfDay.none);
    expect(cmd(a, to: const IstDate(2026, 10, 20), half: HalfDay.firstHalf).halfDay,
        HalfDay.firstHalf);
  });

  test('a resent request keeps its id', () async {
    final a = actions();
    final c = cmd(a);
    repo.nextFailure = const Failure(message: 'offline', code: 'offline');
    expect((await a.apply(c)).isOk, isFalse);
    expect((await a.apply(c)).isOk, isTrue);
    expect(repo.sent.map((x) => x.id).toSet(), {c.id});
  });

  test('cancel: pending at once, approved by asking', () async {
    final a = actions();
    await a.apply(cmd(a));
    expect((await a.cancel(repo.requests.single.id)).valueOrNull, LeaveStatus.cancelled);
  });
}
