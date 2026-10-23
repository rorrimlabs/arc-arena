/// Asking to fix your own attendance after a missed punch. Needs
/// `time_request`; the server checks the times, the overlap and a finalised
/// salary period, and nothing counts until a reviewer approves it.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/repositories/attendance_request_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class AttendanceRequestActions {
  AttendanceRequestActions({
    required this.requests,
    this.guard = const PermissionGuard(null),
  });

  final AttendanceRequestRepository requests;
  final PermissionGuard guard;

  static const _uuid = Uuid();

  /// A new request; keep it to send again after a dropped connection.
  AttendanceRequestCommand prepare({
    required AttendanceRequestKind kind,
    String? entryId,
    DateTime? inAt,
    required DateTime outAt,
    required String reason,
  }) => AttendanceRequestCommand(
    id: _uuid.v4(),
    kind: kind,
    entryId: kind == AttendanceRequestKind.fixOut ? entryId : null,
    inAt: kind == AttendanceRequestKind.add ? inAt : null,
    outAt: outAt,
    reason: reason,
  );

  Future<Result<void>> send(AttendanceRequestCommand cmd) async {
    final denied = guard.check(Permission.timeRequest);
    if (denied != null) return Err(denied);
    if (cmd.reason.trim().isEmpty) {
      return const Err(
        Failure(
          message: 'Say what happened.',
          fix: 'Add a short reason.',
          code: 'reason_required',
        ),
      );
    }
    if (cmd.kind == AttendanceRequestKind.fixOut && cmd.entryId == null) {
      return const Err(
        Failure(
          message: 'Pick the entry to fix.',
          fix: 'Choose the clock-in whose clock-out was missed.',
          code: 'invalid_payload',
        ),
      );
    }
    final inAt = cmd.inAt;
    if (cmd.kind == AttendanceRequestKind.add &&
        (inAt == null ||
            !cmd.outAt.isAfter(inAt) ||
            cmd.outAt.difference(inAt) > const Duration(hours: 24))) {
      return const Err(
        Failure(
          message: 'Those times do not work.',
          fix: 'Clock-out after clock-in, at most 24 hours later.',
          code: 'invalid_times',
        ),
      );
    }
    final res = await requests.request(cmd);
    if (res.isOk) {
      AppTelemetry.addBreadcrumb(
        category: 'attendance',
        message: 'missed_punch_requested',
        data: {'kind': cmd.kind.wire},
      );
    }
    return res;
  }
}

final attendanceRequestActionsProvider = Provider<AttendanceRequestActions>(
  (ref) => AttendanceRequestActions(
    requests: ref.watch(attendanceRequestRepositoryProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
  ),
);
