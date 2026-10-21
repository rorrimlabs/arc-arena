/// Clock in / clock out: the one place a punch is built and sent.
///
/// Every active member may punch for themselves, so the guard only checks that
/// someone active is signed in; the server re-checks membership and applies the
/// arena's location rules. The device time goes along as evidence only.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class AttendanceActions {
  AttendanceActions({
    required this.attendance,
    required this.location,
    required this.clock,
    this.guard = const PermissionGuard(null),
  });

  final AttendanceRepository attendance;
  final LocationProbe location;
  final Clock clock;
  final PermissionGuard guard;

  static const _uuid = Uuid();

  /// One foreground location reading for the punch about to be made.
  Future<LocationReading> readLocation() => location.read();

  /// A new punch for [kind] with [reading]; send it with [send]. Keep the
  /// command to send it again if the connection dropped: the same id can never
  /// be recorded twice.
  PunchCommand prepare(PunchKind kind, LocationReading reading) => PunchCommand(
        punchId: _uuid.v4(),
        kind: kind,
        reading: reading,
        deviceAt: deviceNow(clock),
      );

  Future<Result<PunchOutcome>> send(PunchCommand cmd) async {
    final denied = guard.checkSignedIn();
    if (denied != null) return Err(denied);
    final res = await attendance.punch(cmd);
    if (res case Ok(value: final outcome)) {
      AppTelemetry.addBreadcrumb(
        category: 'attendance',
        message: 'punch_recorded',
        data: {
          'kind': cmd.kind.wire,
          'verdict': outcome.verdict.wire,
          'review': outcome.review,
        },
      );
    }
    return res;
  }
}

final attendanceActionsProvider = Provider<AttendanceActions>(
  (ref) => AttendanceActions(
    attendance: ref.watch(attendanceRepositoryProvider),
    location: ref.watch(locationProbeProvider),
    clock: ref.watch(clockProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
  ),
);
