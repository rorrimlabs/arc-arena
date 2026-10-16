/// The signed-in staff member's own leave. Online only, like attendance.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/leave/leave.dart';

abstract interface class LeaveRepository {
  Future<Result<LeaveBalance>> myBalance();

  /// Newest first.
  Future<Result<List<LeaveRequest>>> myRequests();

  /// Returns the working days the server counted.
  Future<Result<double>> request(LeaveRequestCommand cmd);

  /// Withdraws a pending request, or asks to cancel an approved one.
  /// Returns the new status.
  Future<Result<LeaveStatus>> cancel(String id, {String? reason});
}
