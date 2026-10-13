import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_assign_sheet.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_end_sheet.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_extend_sheet.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_payment_sheet.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The live view of one group session: the single shared countdown at the top
/// (group feature §3) and every player's current system below, each with its own
/// switch / change-game / change-controllers actions (group feature §5–§6).
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final groups = ref.watch(activeGroupsProvider).value ?? const [];
    final g = groups.firstWhereOrNull((x) => x.group.id == groupId);

    if (g == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group session')),
        body: const Center(child: Text('This group session has ended.')),
      );
    }

    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final actions = ref.watch(groupSessionActionsProvider);
    final timer = actions.groupTimer(g.group, warn: ref.watch(warnThresholdProvider));
    final visual = timer.state(now);
    final customer = ref.watch(customerByIdProvider(g.group.primaryCustomerId)).value;
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final resourceName = {for (final r in resources) r.id: r.name};

    final (Color accent, String badge) = switch (visual) {
      SessionVisualState.normal => (arena.stPlaying, 'Playing'),
      SessionVisualState.warning => (arena.stEnding, 'Ending'),
      SessionVisualState.overtime => (arena.stOvertime, 'Over time'),
    };
    final overtime = visual == SessionVisualState.overtime;
    final timerText = overtime
        ? '+${formatClock(timer.overtime(now))}'
        : formatClock(timer.remaining(now));
    final amount = actions.liveBill(g, now).total;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            customer == null ? 'Group' : 'Group · ${customer.displayName}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            ArenaScreenHeader(
              overline:
                  '${g.group.playerCount} players · ${g.group.purchasedControllerCount} controllers',
              title: timerText,
              titleStyle: ArenaType.timer.copyWith(
                fontSize: 56,
                color: overtime ? arena.stOvertime : arena.text,
              ),
              status: Row(
                children: [
                  StatusDotLabel(label: badge, color: accent),
                  const SizedBox(width: AppSpacing.md),
                  Text(overtime ? 'over the shared time' : 'shared time left',
                      style: ArenaType.caption.copyWith(color: arena.textMuted)),
                  const Spacer(),
                  Text(Paise(amount.value).display,
                      style: AppTextStyles.amount(context)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.x5, 0, AppSpacing.x5, AppSpacing.sm),
              child: ArenaSectionLabel(label: 'Players'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: ArenaRowGroup(
                children: [
                  for (final n in g.playerNumbers)
                    _playerRow(context, ref, g, n, resourceName),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showGroupExtendSheet(context, g),
                      icon: const Icon(Icons.more_time),
                      label: const Text('Extend'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showGroupPaymentSheet(context, g),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Payment'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showGroupEndSheet(context, g),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Bill'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerRow(
    BuildContext context,
    WidgetRef ref,
    ActiveGroupSession g,
    int playerNumber,
    Map<String, String> resourceName,
  ) {
    final current = g.currentForPlayer(playerNumber);
    final game = current?.gameId == null
        ? null
        : ref.watch(gameByIdProvider(current!.gameId!)).value;
    // Which physical pads this player holds, by the label written on them —
    // falls back to the count for a count-only assignment.
    final labels = {
      for (final c in ref.watch(controllersProvider).value ?? const [])
        c.id: c.label,
    };
    final pads = current == null
        ? const <String>[]
        : ([
            for (final a
                in ref.watch(openPadAllocationsProvider).value ?? const [])
              if (a.assignmentId == current.id)
                labels[a.controllerId] ?? a.controllerId,
          ]..sort());
    final label = current == null
        ? 'Not on a system'
        : [
            resourceName[current.resourceId] ?? current.resourceId,
            if (game != null) game.name,
            if (pads.isEmpty)
              '${current.controllerCount ?? 1} ctrl'
            else
              pads.join(', '),
          ].join(' · ');

    return ArenaListRow(
      icon: Icons.sports_esports_outlined,
      title: 'Player $playerNumber',
      subtitle: label,
      chevron: false,
      trailing: _PlayerMenu(group: g, playerNumber: playerNumber),
    );
  }
}

class _PlayerMenu extends ConsumerWidget {
  const _PlayerMenu({required this.group, required this.playerNumber});
  final ActiveGroupSession group;
  final int playerNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = group.currentForPlayer(playerNumber);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'switch':
            await showGroupAssignSheet(context,
                group: group, playerNumber: playerNumber, isSwitch: true);
          case 'add':
            await showGroupAssignSheet(context,
                group: group, playerNumber: playerNumber, isSwitch: false);
          case 'game':
            if (current != null) {
              await showGroupChangeGameSheet(context,
                  group: group, current: current);
            }
          case 'controllers':
            if (current != null) {
              await showGroupChangeControllersSheet(context,
                  group: group, current: current);
            }
          case 'end':
            await ref.read(groupSessionActionsProvider).endPlayer(
                  groupId: group.group.id,
                  playerNumber: playerNumber,
                );
        }
      },
      itemBuilder: (context) => current == null
          ? const [
              PopupMenuItem(value: 'add', child: Text('Add to a system')),
            ]
          : const [
              PopupMenuItem(value: 'switch', child: Text('Switch system')),
              PopupMenuItem(value: 'game', child: Text('Change game')),
              PopupMenuItem(value: 'controllers', child: Text('Change controllers')),
              PopupMenuItem(value: 'end', child: Text('End player')),
            ],
    );
  }
}
