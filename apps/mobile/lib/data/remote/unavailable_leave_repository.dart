/// Leave in local-only mode: every call explains it needs the online arena.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/leave_failures.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';

class UnavailableLeaveRepository implements LeaveRepository {
  const UnavailableLeaveRepository();

  @override
  Future<Result<LeaveBalance>> myBalance() async => const Err(LeaveFailures.cloudOnly);

  @override
  Future<Result<List<LeaveRequest>>> myRequests() async =>
      const Err(LeaveFailures.cloudOnly);

  @override
  Future<Result<double>> request(LeaveRequestCommand cmd) async =>
      const Err(LeaveFailures.cloudOnly);

  @override
  Future<Result<LeaveStatus>> cancel(String id, {String? reason}) async =>
      const Err(LeaveFailures.cloudOnly);
}
