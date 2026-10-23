/// My bills in local-only mode: every call explains it needs the online arena.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/bill_failures.dart';
import 'package:arena_ops/domain/bills/my_bill.dart';
import 'package:arena_ops/domain/repositories/my_bills_repository.dart';

class UnavailableMyBillsRepository implements MyBillsRepository {
  const UnavailableMyBillsRepository();

  @override
  Future<Result<List<MyBill>>> forDay(IstDate day) async =>
      const Err(BillFailures.cloudOnly);

  @override
  Future<Result<String>> adjust(BillAdjustCommand cmd) async =>
      const Err(BillFailures.cloudOnly);

  @override
  Future<Result<int>> quote({
    required String resourceId,
    required String activityCode,
    int? controllerCount,
    required DateTime from,
    required DateTime to,
  }) async => const Err(BillFailures.cloudOnly);

  @override
  Future<Result<int>> record(MissedBillCommand cmd) async =>
      const Err(BillFailures.cloudOnly);
}
