import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The exact per-segment history of a session (spec §15).
Future<void> showSessionHistorySheet(BuildContext context, ActiveSession active) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _HistorySheet(active: active),
    ),
  );
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.active});
  final ActiveSession active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final resources = {
      for (final r in ref.watch(resourcesProvider).value ?? []) r.id: r.name,
    };
    final games = {
      for (final g in ref.watch(allGamesProvider).value ?? []) g.id: g.name,
    };
    final theme = Theme.of(context);

    var total = Duration.zero;
    for (final s in active.segments) {
      total += s.playedUpTo(now);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session history', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView(
              children: [
                for (final s in active.segments)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${s.index + 1}',
                          style: theme.textTheme.labelMedium),
                    ),
                    title: Text(
                      '${IstTime.format12(s.startedAt)}–'
                      '${s.endedAt == null ? 'now' : IstTime.format12(s.endedAt!)}',
                      style: AppTextStyles.mono(theme.textTheme.bodyMedium!),
                    ),
                    subtitle: Text([
                      resources[s.resourceId] ?? s.resourceId,
                      s.activityCode,
                      if (s.controllerCount != null) '${s.controllerCount}🎮',
                      if (s.gameId != null) (games[s.gameId] ?? 'Game'),
                    ].join(' · ')),
                    trailing: Text(formatMinutesLabel(s.playedUpTo(now))),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                Text(formatMinutesLabel(total),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
