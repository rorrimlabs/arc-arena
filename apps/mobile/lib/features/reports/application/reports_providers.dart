/// Assembles an [ArenaReport] for a chosen window from the persisted rows.
///
/// All arithmetic lives in the pure [ReportsService]; this layer only fetches.
/// Nothing here invents a figure — an empty arena produces an empty report,
/// not a plausible-looking dashboard.
library;

import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/reports/report_models.dart';
import 'package:arena_ops/domain/reports/reports_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which preset window the Reports tab is showing.
enum ReportPreset { today, week, month, custom }

extension ReportPresetLabel on ReportPreset {
  String get label => switch (this) {
        ReportPreset.today => 'Today',
        ReportPreset.week => 'Week',
        ReportPreset.month => 'Month',
        ReportPreset.custom => 'Custom',
      };
}

/// The selected window. Defaults to today; changing it re-runs the report.
class ReportRangeController extends Notifier<ReportRange> {
  @override
  ReportRange build() {
    final today = IstDate.fromUtc(ref.watch(clockProvider).now());
    return ReportRange.today(today);
  }

  IstDate get _today => IstDate.fromUtc(ref.read(clockProvider).now());

  void select(ReportPreset preset) {
    state = switch (preset) {
      ReportPreset.today => ReportRange.today(_today),
      ReportPreset.week => ReportRange.week(_today),
      ReportPreset.month => ReportRange.month(_today),
      ReportPreset.custom => state,
    };
  }

  void setCustom(IstDate from, IstDate to) {
    // Tolerate a reversed pick rather than producing an empty report.
    state = from.compareTo(to) <= 0
        ? ReportRange.custom(from, to)
        : ReportRange.custom(to, from);
  }

  /// Which preset chip to highlight for the current range.
  ReportPreset get preset {
    final today = _today;
    if (state == ReportRange.today(today)) return ReportPreset.today;
    if (state == ReportRange.week(today)) return ReportPreset.week;
    if (state == ReportRange.month(today)) return ReportPreset.month;
    return ReportPreset.custom;
  }
}

final reportRangeProvider =
    NotifierProvider<ReportRangeController, ReportRange>(
  ReportRangeController.new,
);

/// The report for the window the Reports tab is showing.
final arenaReportProvider = FutureProvider.autoDispose<ArenaReport>(
  (ref) => ref.watch(reportForRangeProvider(ref.watch(reportRangeProvider)).future),
);

/// The report for any window — used by the Reports tab and by the session log,
/// which looks further back without disturbing the tab's own selection.
final reportForRangeProvider =
    FutureProvider.autoDispose.family<ArenaReport, ReportRange>(
        (ref, range) async {
  // Recompute when the floor changes, so "today" stays live.
  ref.watch(activeSessionsProvider);
  ref.watch(awaitingPaymentProvider);
  // …and when another device's bills or payments arrive by sync.
  ref.watch(syncRevisionProvider);

  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final groupRepo = ref.watch(groupSessionRepositoryProvider);
  final catalog = ref.watch(catalogRepositoryProvider);
  final customerRepo = ref.watch(customerRepositoryProvider);

  final from = range.startUtc;
  final to = range.endUtc;

  // Independent reads, issued together.
  final sessions = sessionRepo.inRange(from, to);
  final segments = sessionRepo.segmentsInRange(from, to);
  final charges = sessionRepo.chargesInRange(from, to);
  final payments = sessionRepo.paymentsInRange(from, to);
  final groups = groupRepo.inRange(from, to);
  final assignments = groupRepo.assignmentsInRange(from, to);
  final groupCharges = groupRepo.chargesInRange(from, to);
  final groupPayments = groupRepo.paymentsInRange(from, to);
  final customers = customerRepo.all();
  final resources = catalog.resources();
  final games = catalog.games();
  final activities = catalog.activities();
  final snapshot = catalog.currentSnapshot();

  return const ReportsService().build(ReportInput(
    range: range,
    sessions: await sessions,
    segments: await segments,
    charges: await charges,
    payments: await payments,
    groups: await groups,
    groupAssignments: await assignments,
    groupCharges: await groupCharges,
    groupPayments: await groupPayments,
    customers: await customers,
    resources: await resources,
    gameNames: {for (final g in await games) g.id: g.name},
    activityNames: {for (final a in await activities) a.code: a.name},
    // Operating hours decide the utilisation denominator, so the report uses
    // the same calendar the pricing engine does.
    calendar: (await snapshot).calendar,
  ));
});
