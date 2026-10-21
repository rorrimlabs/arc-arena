/// Riverpod wiring for the staff member's own leave (online only).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/unavailable_leave_repository.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in cloud mode with the server-backed repository.
final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => const UnavailableLeaveRepository(),
);

final myLeaveBalanceProvider = FutureProvider.autoDispose<Result<LeaveBalance>>(
  (ref) => ref.watch(leaveRepositoryProvider).myBalance(),
);

final myLeaveRequestsProvider =
    FutureProvider.autoDispose<Result<List<LeaveRequest>>>(
  (ref) => ref.watch(leaveRepositoryProvider).myRequests(),
);
