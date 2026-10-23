/// [AttendanceRequestRepository] straight against the server: requests are
/// read through RLS (your own rows) and sent to sync_push at once as
/// `attendance.request` (the request id doubles as the op id).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/attendance_request_failures.dart';
import 'package:arena_ops/data/remote/online_calls.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';
import 'package:arena_ops/domain/repositories/attendance_request_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAttendanceRequestRepository
    implements AttendanceRequestRepository {
  SupabaseAttendanceRequestRepository({
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

  /// Called after the server recorded a request (to nudge other devices).
  final void Function()? onChanged;
  final Duration timeout;

  String? _staffId;

  @override
  Future<Result<List<AttendanceRequest>>>
  myRequests() => onlineRead(_client, () async {
    final rows = await _client
        .from('attendance_requests')
        .select(
          'id, kind, in_at, out_at, reason, status, decision_note, created_at',
        )
        .eq('arena_id', arenaId)
        .eq('staff_id', await _myStaffId())
        .order('created_at', ascending: false)
        .limit(50)
        .timeout(timeout);
    return [for (final r in rows) AttendanceRequest.fromJson(r)];
  });

  @override
  Future<Result<void>> request(AttendanceRequestCommand cmd) async {
    final res = await pushNow(
      _transport,
      arenaId: arenaId,
      deviceId: await deviceId(),
      opId: cmd.id,
      kind: 'attendance.request',
      payload: cmd.toPayload(),
      rejected: AttendanceRequestFailures.rejected,
    );
    if (res.isOk) onChanged?.call();
    return switch (res) {
      Ok() => const Ok(null),
      Err(failure: final f) => Err(f),
    };
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
