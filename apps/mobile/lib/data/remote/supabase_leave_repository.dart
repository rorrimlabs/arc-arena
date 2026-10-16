/// [LeaveRepository] straight against the server: requests and the balance are
/// read online through RLS and the leave_balances RPC; a request or a
/// cancellation goes to sync_push at once (its id doubles as the op id).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/leave_failures.dart';
import 'package:arena_ops/data/remote/online_calls.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseLeaveRepository implements LeaveRepository {
  SupabaseLeaveRepository({
    required this._client,
    required this._transport,
    required this.arenaId,
    required this.userId,
    required this.deviceId,
    this.onChanged,
    this.timeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;
  final SyncTransport _transport;
  final String arenaId;
  final String userId;
  final Future<String> Function() deviceId;

  /// Called after the server recorded a change (to nudge other devices).
  final void Function(String kind)? onChanged;
  final Duration timeout;

  String? _staffId;

  @override
  Future<Result<LeaveBalance>> myBalance() => onlineRead(_client, () async {
        final rows = await _client.rpc('leave_balances', params: {
          'p_arena': arenaId,
          'p_staff': await _myStaffId(),
        }).timeout(timeout);
        return LeaveBalance.fromJson(
            Map<String, dynamic>.from((rows as List).single as Map));
      });

  @override
  Future<Result<List<LeaveRequest>>> myRequests() => onlineRead(_client, () async {
        final rows = await _client
            .from('leave_requests')
            .select('id, kind, from_date, to_date, half_day, days, paid_days, '
                'lop_days, reason, status, decision_note, decided_at, created_at')
            .eq('arena_id', arenaId)
            .eq('staff_id', await _myStaffId())
            .order('from_date', ascending: false)
            .limit(100)
            .timeout(timeout);
        return [for (final r in rows) LeaveRequest.fromJson(r)];
      });

  @override
  Future<Result<double>> request(LeaveRequestCommand cmd) async {
    final res = await _push('leave.request', cmd.id, cmd.toPayload());
    return switch (res) {
      Ok(value: final r) => Ok((r['days'] as num).toDouble()),
      Err(failure: final f) => Err(f),
    };
  }

  @override
  Future<Result<LeaveStatus>> cancel(String id, {String? reason}) async {
    final res = await _push('leave.cancel', const Uuid().v4(),
        {'id': id, if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
    return switch (res) {
      Ok(value: final r) => Ok(LeaveStatus.fromWire(r['status'] as String?)),
      Err(failure: final f) => Err(f),
    };
  }

  Future<Result<Map<String, dynamic>>> _push(
      String kind, String opId, Map<String, dynamic> payload) async {
    final res = await pushNow(
      _transport,
      arenaId: arenaId,
      deviceId: await deviceId(),
      opId: opId,
      kind: kind,
      payload: payload,
      rejected: LeaveFailures.rejected,
    );
    if (res.isOk) onChanged?.call(kind);
    return res;
  }

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
}
