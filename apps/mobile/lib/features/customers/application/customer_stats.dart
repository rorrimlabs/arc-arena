/// Derived customer statistics (spec §21). Computed from session/payment facts,
/// never stored as a primary source of truth.
library;

import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class CustomerStats {
  const CustomerStats({
    required this.visits,
    required this.sessions,
    required this.gamingMinutes,
    required this.totalSpentPaise,
    required this.favouriteActivity,
    required this.mostPlayedGame,
    required this.lastVisit,
  });

  final int visits;
  final int sessions;
  final int gamingMinutes;
  final int totalSpentPaise;
  final String? favouriteActivity;
  final String? mostPlayedGame;
  final DateTime? lastVisit;

  Paise get totalSpent => Paise(totalSpentPaise);
  double get gamingHours => gamingMinutes / 60.0;
  Paise get averageSpend => Paise(visits == 0 ? 0 : totalSpentPaise ~/ visits);
}

final customerStatsProvider =
    FutureProvider.autoDispose.family<CustomerStats, String>((ref, id) async {
  final sessionsRepo = ref.watch(sessionRepositoryProvider);
  final sessions = (await sessionsRepo.forCustomer(id))
      .where((s) => s.status != SessionStatus.voided)
      .toList();

  var totalPaid = 0;
  var gamingMinutes = 0;
  final visitDays = <String>{};
  final activityCounts = <String, int>{};
  final gameCounts = <String, int>{};
  DateTime? lastVisit;

  for (final s in sessions) {
    visitDays.add(IstDate.fromUtc(s.startedAt).iso);
    // Favourite activity / top game come from the segments actually played.
    for (final seg in await sessionsRepo.segmentsFor(s.id)) {
      activityCounts.update(seg.activityCode, (v) => v + 1, ifAbsent: () => 1);
      if (seg.gameId != null) {
        gameCounts.update(seg.gameId!, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    if (s.actualEndedAt != null) {
      gamingMinutes += s.actualEndedAt!.difference(s.startedAt).inMinutes;
    }
    if (lastVisit == null || s.startedAt.isAfter(lastVisit)) {
      lastVisit = s.startedAt;
    }
    for (final p in await sessionsRepo.paymentsFor(s.id)) {
      totalPaid += p.amountPaise;
    }
  }

  String? topGameName;
  final topGameId = _modeKey(gameCounts);
  if (topGameId != null) {
    topGameName = (await ref.watch(catalogRepositoryProvider).gameById(topGameId))?.name;
  }

  return CustomerStats(
    visits: visitDays.length,
    sessions: sessions.length,
    gamingMinutes: gamingMinutes,
    totalSpentPaise: totalPaid,
    favouriteActivity: _modeKey(activityCounts),
    mostPlayedGame: topGameName,
    lastVisit: lastVisit,
  );
});

String? _modeKey(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  var best = counts.entries.first;
  for (final e in counts.entries) {
    if (e.value > best.value) best = e;
  }
  return best.key;
}
