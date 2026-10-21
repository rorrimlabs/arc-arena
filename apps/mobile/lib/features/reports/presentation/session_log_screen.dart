import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/reports/report_models.dart';
import 'package:arena_ops/features/reports/application/reports_providers.dart';
import 'package:arena_ops/features/reports/presentation/session_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Every session, searchable" (design: More → Session log; brief §12).
///
/// Staff use this to answer "what did they play last time?" and "who had HEX
/// this afternoon?", so it looks back further than the Reports tab's window
/// and has its own range — changing it here does not move the owner's report.
class SessionLogScreen extends ConsumerStatefulWidget {
  const SessionLogScreen({super.key});

  static const String path = '/session-log';

  @override
  ConsumerState<SessionLogScreen> createState() => _SessionLogScreenState();
}

class _SessionLogScreenState extends ConsumerState<SessionLogScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final today = IstDate.fromUtc(ref.watch(clockProvider).now());
    final range = ReportRange.custom(today.addDays(-(_days - 1)), today);
    final async = ref.watch(reportForRangeProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session log'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            // Scrolls rather than overflowing on a narrow phone.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in const [7, 30, 90]) ...[
                    ChoiceChip(
                      label: Text(d == 7 ? 'Last week' : 'Last $d days'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      body: switch (async) {
        AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('Could not load the log: $error',
                  style: TextStyle(color: arena.danger)),
            ),
          ),
        AsyncData(:final value) => _Body(report: value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Reuses the history list the Reports tab shows, so both read identically.
/// Bill amounts only for those who handle money (bill, money or reports), the
/// same people the server lets read payment rows.
class _Body extends ConsumerWidget {
  const _Body({required this.report});
  final ArenaReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final showMoney = user != null &&
        (user.can(Permission.bill) ||
            user.can(Permission.money) ||
            user.can(Permission.reports));
    return SessionHistoryBody(report: report, showMoney: showMoney);
  }
}
