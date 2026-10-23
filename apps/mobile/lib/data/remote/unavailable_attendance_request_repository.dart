/// Attendance requests in local-only mode: they need the online arena.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';
import 'package:arena_ops/domain/repositories/attendance_request_repository.dart';

class UnavailableAttendanceRequestRepository
    implements AttendanceRequestRepository {
  const UnavailableAttendanceRequestRepository();

  @override
  Future<Result<List<AttendanceRequest>>> myRequests() async =>
      const Err(AttendanceFailures.cloudOnly);

  @override
  Future<Result<void>> request(AttendanceRequestCommand cmd) async =>
      const Err(AttendanceFailures.cloudOnly);
}
