import 'dart:io';

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/supabase_leave_repository.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/scripted_transport.dart';

void main() {
  late ScriptedTransport transport;
  late SupabaseLeaveRepository repo;
  final changed = <String>[];

  const cmd = LeaveRequestCommand(
    id: '22222222-2222-4222-8222-222222222222',
    kind: LeaveKind.unplanned,
    from: IstDate(2026, 10, 14),
    to: IstDate(2026, 10, 15),
    reason: 'fever',
  );

  setUp(() {
    transport = ScriptedTransport();
    changed.clear();
    repo = SupabaseLeaveRepository(
      client: SupabaseClient('http://127.0.0.1:9', 'test-key'),
      transport: transport,
      arenaId: 'arena-1',
      userId: 'user-1',
      deviceId: () async => 'device-1',
      onChanged: changed.add,
    );
  });

  test('a request is one leave.request op whose id is the request id', () async {
    transport.onPush = (op) =>
        OpResult(opId: op.opId, status: 'applied', result: {'days': 2.0});
    expect((await repo.request(cmd)).valueOrNull, 2);
    final op = transport.pushed.single;
    expect(op.opId, cmd.id);
    expect(op.kind, 'leave.request');
    expect(op.payload, cmd.toPayload());
    expect(changed, ['leave.request']);
  });

  test('every refusal has its own words and a fix', () async {
    for (final code in [
      'reason_required', 'invalid_dates', 'half_day_not_allowed', 'planned_in_past',
      'too_far_back', 'no_working_days', 'leave_overlap', 'period_finalised',
      'invalid_state', 'not_found', 'duplicate',
    ]) {
      transport.onPush = (op) => OpResult(opId: op.opId, status: 'rejected', error: code);
      final f = (await repo.request(cmd)).failureOrNull!;
      expect(f.code, code);
      expect(f.message, isNot(contains(code)));
      expect(f.fix, isNotNull);
    }
    expect(changed, isEmpty);
  });

  test('cancel answers the new status; offline is offline', () async {
    transport.onPush = (op) =>
        OpResult(opId: op.opId, status: 'applied', result: {'status': 'cancel_pending'});
    expect((await repo.cancel('r1', reason: 'trip off')).valueOrNull, LeaveStatus.cancelPending);
    expect(transport.pushed.single.payload, {'id': 'r1', 'reason': 'trip off'});
    transport.pushThrows = SyncOfflineException(const SocketException('down'));
    expect((await repo.cancel('r1')).failureOrNull!.code, 'offline');
  });

  test('reads without a session ask to sign in again', () async {
    expect((await repo.myBalance()).failureOrNull!.code, 'not_signed_in');
    expect((await repo.myRequests()).failureOrNull!.code, 'not_signed_in');
  });
}
