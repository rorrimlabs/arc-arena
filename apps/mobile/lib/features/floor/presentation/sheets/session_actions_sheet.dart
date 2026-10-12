import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/features/floor/presentation/sheets/change_controllers_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/change_game_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/extend_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/session_history_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/switch_system_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/take_payment_sheet.dart';
import 'package:arena_ops/features/floor/presentation/station_detail_screen.dart';
import 'package:arena_ops/features/games/presentation/controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every in-session action for one station, one tap from the floor card
/// (brief §3). Each row routes to the existing sheet, so no timing, pricing or
/// resource logic lives here.
Future<void> showSessionActionsSheet(
  BuildContext context,
  ActiveSession active,
) {
  return showModalBottomSheet<void>(
    context: context,
    // The full action list is taller than the default half-sheet, so let it
    // take the height it needs and scroll on a short screen.
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SessionActionsSheet(active: active),
  );
}

class _SessionActionsSheet extends ConsumerWidget {
  const _SessionActionsSheet({required this.active});

  final ActiveSession active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = active.current;
    final activities = ref.watch(activitiesProvider).value ?? const [];
    final activity = activities
        .where((a) => a.code == current.activityCode)
        .firstOrNull;
    final usesGames = activity?.usesGames ?? false;
    final usesControllers = activity?.usesControllers ?? false;
    final resources = ref.watch(resourcesProvider).value ?? const [];
    final resName = resources
        .where((r) => r.id == current.resourceId)
        .map((r) => r.name)
        .firstOrNull;

    // Pop the sheet first so the action's own sheet isn't stacked under it.
    void run(void Function() action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x5,
                0,
                AppSpacing.x5,
                AppSpacing.sm,
              ),
              child: Text(
                resName ?? current.resourceId,
                style: ArenaType.h3.copyWith(color: context.arena.text),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_full),
              title: const Text('View session'),
              onTap: () => run(
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        StationDetailScreen(sessionId: active.session.id),
                  ),
                ),
              ),
            ),
            if (current.gameId != null)
              ListTile(
                leading: const Icon(Icons.sports_esports_outlined),
                title: const Text('Game controls'),
                onTap: () =>
                    run(() => showControlsSheet(context, current.gameId!)),
              ),
            if (usesGames)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Change game'),
                onTap: () => run(() => showChangeGameSheet(context, active)),
              ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Change system'),
              subtitle: const Text('Keeps the same clock and bill'),
              onTap: () => run(() => showSwitchSystemSheet(context, active)),
            ),
            if (usesControllers)
              ListTile(
                leading: const Icon(Icons.videogame_asset_outlined),
                title: const Text('Change controllers'),
                onTap: () =>
                    run(() => showChangeControllersSheet(context, active)),
              ),
            ListTile(
              leading: const Icon(Icons.more_time),
              title: const Text('Extend session'),
              onTap: () => run(() => showExtendSheet(context, active)),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Record payment'),
              subtitle: const Text('Take money now, keep playing'),
              onTap: () =>
                  run(() => showTakePaymentSheet(context, active.session)),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Session history'),
              onTap: () => run(() => showSessionHistorySheet(context, active)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('End and bill'),
              onTap: () => run(() => showEndSessionSheet(context, active)),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
