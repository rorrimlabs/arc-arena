import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_bar_chart.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/domain/reports/report_models.dart';
import 'package:arena_ops/features/reports/application/report_export.dart';
import 'package:arena_ops/features/reports/application/reports_providers.dart';
import 'package:arena_ops/features/reports/presentation/session_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The owner's reports (brief §13). Every figure is computed from persisted
/// sessions, segments, charge rows and payment rows for the chosen window —
/// there are no sample numbers anywhere on this screen, so an arena that has
/// not traded yet shows zeroes and an empty state rather than a demo.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static const String path = '/reports';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final async = ref.watch(arenaReportProvider);
    final range = ref.watch(reportRangeProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(arenaReportProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              ArenaScreenHeader(
                title: 'Reports',
                overline: range.label,
                trailing: _ExportButton(report: async.value),
              ),
              const ConnectionStatus(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.x5),
                child: _RangePicker(),
              ),
              const SizedBox(height: AppSpacing.lg),
              switch (async) {
                AsyncError(:final error) => _Message(
                    icon: Icons.error_outline,
                    title: 'Could not build the report',
                    body: '$error',
                  ),
                AsyncData(:final value) => _Report(report: value),
                _ => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              },
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
                child: Text(
                  'Figures come from recorded sessions and payments in this '
                  'period. Running sessions are not billed yet, so they are '
                  'counted in gaming hours but not in billed takings.',
                  style: ArenaType.caption.copyWith(color: arena.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePicker extends ConsumerWidget {
  const _RangePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reportRangeProvider.notifier);
    ref.watch(reportRangeProvider);
    final selected = controller.preset;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in ReportPreset.values)
          ChoiceChip(
            label: Text(p.label),
            selected: selected == p,
            onSelected: (_) async {
              if (p == ReportPreset.custom) {
                await _pickCustom(context, ref);
              } else {
                controller.select(p);
              }
            },
          ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    // The arena's (IST) today from the app clock, not the device's.
    final today = IstDate.fromUtc(ref.read(clockProvider).now());
    final now = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      currentDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      helpText: 'Report period',
    );
    if (picked == null) return;
    ref.read(reportRangeProvider.notifier).setCustom(
          IstDate(picked.start.year, picked.start.month, picked.start.day),
          IstDate(picked.end.year, picked.end.month, picked.end.day),
        );
  }
}

class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton({required this.report});
  final ArenaReport? report;

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return IconButton(
      tooltip: 'Export to Excel',
      onPressed: report == null || _busy ? null : () => _export(report),
      icon: _busy
          ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.ios_share, color: context.arena.text),
    );
  }

  Future<void> _export(ArenaReport report) async {
    setState(() => _busy = true);
    try {
      final file = await const ReportExporter().writeToFile(report);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '404 Arena report · ${report.range.label}',
        ),
      );
    } catch (e) {
      if (mounted) {
        showToast(context, 'Export failed. Try again.', kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return const _Message(
        icon: Icons.insights_outlined,
        title: 'Nothing recorded yet',
        body: 'Sessions and payments in this period will show up here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
          child: _Headline(report: report),
        ),
        if (report.byDay.length > 1) ...[
          const SizedBox(height: AppSpacing.xl),
          const ArenaSectionLabel(label: 'Takings by day'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
            child: _ByDay(report: report),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const ArenaSectionLabel(label: 'Revenue by activity'),
        _MoneyRows(rows: report.byActivity, emptyNote: 'No billed charges yet.'),
        const SizedBox(height: AppSpacing.xl),
        const ArenaSectionLabel(label: 'Collected by payment method'),
        _MoneyRows(rows: report.byMethod, emptyNote: 'Nothing collected yet.'),
        const SizedBox(height: AppSpacing.xl),
        const ArenaSectionLabel(label: 'Revenue by price band'),
        _MoneyRows(rows: report.byBand, emptyNote: 'No billed charges yet.'),
        const SizedBox(height: AppSpacing.xl),
        ArenaSectionLabel(
          label: 'Station utilisation',
          trailing: '${(report.averageUtilisation * 100).round()}% average',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
          child: _Utilisation(report: report),
        ),
        const SizedBox(height: AppSpacing.xl),
        const ArenaSectionLabel(label: 'Most played games'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
          child: _TopGames(report: report),
        ),
        const SizedBox(height: AppSpacing.xl),
        ArenaSectionLabel(
          label: 'Sessions',
          trailing: '${report.history.length} in period',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
          child: FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SessionHistoryScreen(report: report),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Session & customer history'),
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: arena.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: arena.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Collected',
                  style: ArenaType.caption.copyWith(color: arena.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                report.collected.display,
                style: ArenaType.display.copyWith(color: arena.text, fontSize: 44),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${report.billed.display} billed · '
                '${report.pending.display} pending',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Sessions',
                value: '${report.sessionCount}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Stat(
                label: 'Gaming hours',
                value: report.gamingHours.toStringAsFixed(1),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Stat(
                label: 'Customers',
                value: '${report.uniqueCustomers}',
                sub: report.newCustomers > 0 ? '${report.newCustomers} new' : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ArenaType.h2.copyWith(color: arena.text)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ArenaType.caption.copyWith(color: arena.textMuted)),
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArenaType.caption.copyWith(color: arena.primary)),
        ],
      ),
    );
  }
}

class _ByDay extends StatelessWidget {
  const _ByDay({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final days = report.byDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArenaBarChart(
          values: [for (final d in days) d.collectedPaise],
          // Label the ends, and every bar when there are few enough to read.
          labels: [
            for (var i = 0; i < days.length; i++)
              if (days.length <= 7 || i == 0 || i == days.length - 1)
                '${days[i].day.day}'
              else
                '',
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Collected per day · ${days.first.day.iso} → ${days.last.day.iso}',
          style: ArenaType.caption.copyWith(color: arena.textSubtle),
        ),
      ],
    );
  }
}

class _MoneyRows extends StatelessWidget {
  const _MoneyRows({required this.rows, required this.emptyNote});
  final List<MoneyRow> rows;
  final String emptyNote;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final shown = rows.where((r) => r.paise != 0 || r.count != 0).toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
        child: Text(emptyNote,
            style: ArenaType.caption.copyWith(color: arena.textSubtle)),
      );
    }
    final total = shown.fold<int>(0, (a, r) => a + r.paise);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
      child: Column(
        children: [
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.label,
                        style: ArenaType.body.copyWith(color: arena.text)),
                  ),
                  if (total > 0)
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${((r.paise / total) * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: ArenaType.caption.copyWith(color: arena.textSubtle),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    Paise(r.paise).display,
                    style: AppTextStyles.mono(ArenaType.label)
                        .copyWith(color: arena.text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Utilisation extends StatelessWidget {
  const _Utilisation({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Column(
      children: [
        for (final u in report.resourceUsage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(u.resourceName,
                          style: ArenaType.label.copyWith(color: arena.text)),
                    ),
                    Text(
                      '${formatMinutesLabel(Duration(minutes: u.playedMinutes))}'
                      ' · ${(u.utilisation * 100).round()}%',
                      style: AppTextStyles.mono(ArenaType.caption)
                          .copyWith(color: arena.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: u.utilisation.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: arena.tmTrack,
                    color: arena.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopGames extends StatelessWidget {
  const _TopGames({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    if (report.topGames.isEmpty) {
      return Text('No game time recorded in this period.',
          style: ArenaType.caption.copyWith(color: arena.textSubtle));
    }
    return Column(
      children: [
        for (final g in report.topGames.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(g.gameName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ArenaType.body.copyWith(color: arena.text)),
                ),
                Text(
                  '${g.sessions} session${g.sessions == 1 ? '' : 's'}',
                  style: ArenaType.caption.copyWith(color: arena.textSubtle),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatMinutesLabel(Duration(minutes: g.playedMinutes)),
                  style: AppTextStyles.mono(ArenaType.label)
                      .copyWith(color: arena.text),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          Icon(icon, size: 34, color: arena.textSubtle),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: ArenaType.h3.copyWith(color: arena.text)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
        ],
      ),
    );
  }
}
