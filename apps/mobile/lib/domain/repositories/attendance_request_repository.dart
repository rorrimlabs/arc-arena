/// The signed-in person's own attendance requests (missed punches). Online
/// only, like attendance; a reviewer decides them on the admin dashboard.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';

abstract interface class AttendanceRequestRepository {
  /// Newest first.
  Future<Result<List<AttendanceRequest>>> myRequests();

  Future<Result<void>> request(AttendanceRequestCommand cmd);
}
