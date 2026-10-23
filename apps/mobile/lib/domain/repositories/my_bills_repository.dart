/// The signed-in staff member's own closed bills, and changing one's total.
/// Online only, like leave: the server checks the permission and that the
/// bill is theirs.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/bills/my_bill.dart';

abstract interface class MyBillsRepository {
  /// Bills that closed on [day] (IST), newest first.
  Future<Result<List<MyBill>>> forDay(IstDate day);

  /// Returns the bill's payment status after the change.
  Future<Result<String>> adjust(BillAdjustCommand cmd);

  /// What a missed bill would cost on the current price list (total, paise).
  Future<Result<int>> quote({
    required String resourceId,
    required String activityCode,
    int? controllerCount,
    required DateTime from,
    required DateTime to,
  });

  /// Adds a missed bill; returns its total.
  Future<Result<int>> record(MissedBillCommand cmd);
}
