/// Riverpod wiring for the staff member's own bills (online only).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/unavailable_my_bills_repository.dart';
import 'package:arena_ops/domain/bills/my_bill.dart';
import 'package:arena_ops/domain/repositories/my_bills_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in cloud mode with the server-backed repository.
final myBillsRepositoryProvider = Provider<MyBillsRepository>(
  (ref) => const UnavailableMyBillsRepository(),
);

final myBillsForDayProvider = FutureProvider.autoDispose
    .family<Result<List<MyBill>>, IstDate>(
      (ref, day) => ref.watch(myBillsRepositoryProvider).forDay(day),
    );
