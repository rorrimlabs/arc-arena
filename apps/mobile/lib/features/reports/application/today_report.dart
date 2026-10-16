/// Today's business summary (spec §27–§28). Business day = Asia/Kolkata date.
/// Reads stored facts; never recomputes historical pricing.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class TodaySummary {
  const TodaySummary({
    required this.date,
    required this.billedPaise,
    required this.collectedPaise,
    required this.waivedPaise,
    required this.sessions,
    required this.activeNow,
    required this.uniqueCustomers,
    required this.gamingMinutes,
  });

  final IstDate date;
  final int billedPaise;
  final int collectedPaise;
  final int waivedPaise;
  final int sessions;
  final int activeNow;
  final int uniqueCustomers;
  final int gamingMinutes;

  /// Pending = billed − collected − waived (spec §28).
  int get pendingPaise => billedPaise - collectedPaise - waivedPaise;

  Paise get billed => Paise(billedPaise);
  Paise get collected => Paise(collectedPaise);
  Paise get pending => Paise(pendingPaise);
  double get gamingHours => gamingMinutes / 60.0;
}

/// Recomputes when sessions change. Not tied to the 1-second ticker, so active
/// gaming minutes are approximate between refreshes — fine for a glance strip.
final todaySummaryProvider = FutureProvider.autoDispose<TodaySummary>((ref) async {
  // Rebuild whenever the set of active sessions changes.
  ref.watch(activeSessionsProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  final now = ref.watch(clockProvider).now();
  final date = IstDate.fromUtc(now);
  final from = date.startOfDayUtc();
  final to = date.endOfDayUtc();

  final sessions = (await repo.inRange(from, to))
      .where((s) => s.status != SessionStatus.voided)
      .toList();
  final payments = await repo.paymentsInRange(from, to);

  var billed = 0;
  var waived = 0;
  var gamingMinutes = 0;
  final customers = <String>{};
  for (final s in sessions) {
    customers.add(s.customerId);
    if (s.billedAmountPaise != null) billed += s.billedAmountPaise!;
    if (s.paymentStatus == PaymentStatus.waived) {
      waived += s.billedAmountPaise ?? 0;
    }
    final end = s.actualEndedAt ?? now;
    gamingMinutes += end.difference(s.startedAt).inMinutes.clamp(0, 1 << 31);
  }
  final collected = payments.fold<int>(0, (a, p) => a + p.amountPaise);
  final activeNow = sessions.where((s) => s.status == SessionStatus.active).length;

  return TodaySummary(
    date: date,
    billedPaise: billed,
    collectedPaise: collected,
    waivedPaise: waived,
    sessions: sessions.length,
    activeNow: activeNow,
    uniqueCustomers: customers.length,
    gamingMinutes: gamingMinutes,
  );
});
