/// Applying for and cancelling your own leave. Any active member may; the
/// server checks the dates, counts the working days and keeps the rules.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/leave_providers.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class LeaveActions {
  LeaveActions({required this.leave, this.guard = const PermissionGuard(null)});

  final LeaveRepository leave;
  final PermissionGuard guard;

  static const _uuid = Uuid();

  /// A new request; keep it to send again after a dropped connection.
  LeaveRequestCommand prepare({
    required LeaveKind kind,
    required IstDate from,
    required IstDate to,
    HalfDay halfDay = HalfDay.none,
    required String reason,
  }) =>
      LeaveRequestCommand(
        id: _uuid.v4(),
        kind: kind,
        from: from,
        to: to,
        halfDay: from == to ? halfDay : HalfDay.none,
        reason: reason,
      );

  /// Returns the working days the server counted.
  Future<Result<double>> apply(LeaveRequestCommand cmd) async {
    final denied = guard.checkSignedIn();
    if (denied != null) return Err(denied);
    if (cmd.reason.trim().isEmpty) {
      return const Err(Failure(
          message: 'Say why you need the leave.',
          fix: 'Add a short reason.',
          code: 'reason_required'));
    }
    if (cmd.to.compareTo(cmd.from) < 0) {
      return const Err(Failure(
          message: 'The last day is before the first.',
          fix: 'Pick an end date on or after the start.',
          code: 'invalid_dates'));
    }
    final res = await leave.request(cmd);
    if (res.isOk) {
      AppTelemetry.addBreadcrumb(
          category: 'leave', message: 'leave_requested', data: {'kind': cmd.kind.wire});
    }
    return res;
  }

  Future<Result<LeaveStatus>> cancel(String id, {String? reason}) async {
    final denied = guard.checkSignedIn();
    if (denied != null) return Err(denied);
    return leave.cancel(id, reason: reason);
  }
}

final leaveActionsProvider = Provider<LeaveActions>(
  (ref) => LeaveActions(
    leave: ref.watch(leaveRepositoryProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
  ),
);
