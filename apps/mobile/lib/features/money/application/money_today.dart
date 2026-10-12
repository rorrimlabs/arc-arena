/// Today's money, derived read-only from stored payment rows (spec §20, §27).
///
/// Presentation only — never recomputes pricing. Buckets the real payment
/// records for the business day (Asia/Kolkata) by method and by hour.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/payment.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// IST is a fixed +5:30 offset (no DST), so hour-of-day is a plain shift.
int istHourOf(DateTime utc) =>
    utc.toUtc().add(const Duration(hours: 5, minutes: 30)).hour;

/// All of today's payment rows, newest first.
final todayPaymentsProvider = FutureProvider.autoDispose<List<Payment>>((ref) async {
  ref.watch(activeSessionsProvider); // refresh as the floor changes
  final repo = ref.watch(sessionRepositoryProvider);
  final now = ref.watch(clockProvider).now();
  final date = IstDate.fromUtc(now);
  final rows = await repo.paymentsInRange(date.startOfDayUtc(), date.endOfDayUtc());
  rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return rows;
});

@immutable
class MethodBreakdown {
  const MethodBreakdown(this.method, this.totalPaise, this.count);
  final PaymentMethod method;
  final int totalPaise;
  final int count;
}

/// Totals per payment method for today (UPI, Cash, Card, Other), in a stable
/// display order, including methods with no takings yet.
final todayMethodBreakdownProvider =
    FutureProvider.autoDispose<List<MethodBreakdown>>((ref) async {
  final payments = await ref.watch(todayPaymentsProvider.future);
  const order = [
    PaymentMethod.upi,
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.other,
  ];
  final totals = {for (final m in order) m: 0};
  final counts = {for (final m in order) m: 0};
  for (final p in payments) {
    totals[p.method] = (totals[p.method] ?? 0) + p.amountPaise;
    counts[p.method] = (counts[p.method] ?? 0) + 1;
  }
  return [for (final m in order) MethodBreakdown(m, totals[m]!, counts[m]!)];
});

/// Collected paise bucketed into 24 hours (index = IST hour), for the Today
/// takings chart. Empty hours are zero.
final todayHourlyTakingsProvider =
    FutureProvider.autoDispose<List<int>>((ref) async {
  final payments = await ref.watch(todayPaymentsProvider.future);
  final buckets = List<int>.filled(24, 0);
  for (final p in payments) {
    buckets[istHourOf(p.createdAt)] += p.amountPaise;
  }
  return buckets;
});

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.upi => 'UPI',
        PaymentMethod.cash => 'Cash',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}
