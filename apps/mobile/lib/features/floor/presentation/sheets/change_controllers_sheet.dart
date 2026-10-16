import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Change how many controllers — and which physical pads — a running session
/// uses (spec §12, allocation brief §8). The pads it holds start picked, so
/// replacing a faulty pad is un-pick + pick. Applying opens a new segment at
/// that instant: the new count is billed only from now, removed pads are
/// released and added ones reserved in one transaction, and the session's
/// start time and timer are untouched.
Future<void> showChangeControllersSheet(BuildContext context, ActiveSession active) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ChangeControllersSheet(active: active),
  );
}

class _ChangeControllersSheet extends ConsumerStatefulWidget {
  const _ChangeControllersSheet({required this.active});
  final ActiveSession active;

  @override
  ConsumerState<_ChangeControllersSheet> createState() =>
      _ChangeControllersSheetState();
}

class _ChangeControllersSheetState
    extends ConsumerState<_ChangeControllersSheet> {
  ControllerChoice? _choice;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.active.current;
    final openAsync = ref.watch(openPadAllocationsProvider);
    final held = <String>[
      for (final a in openAsync.value ?? const [])
        if (a.segmentId == current.id) a.controllerId,
    ]..sort();
    final heldSet = held.toSet();
    final initial = held.isEmpty
        ? ControllerChoice.count(current.controllerCount)
        : ControllerChoice.tracked(requested: held.length, padIds: held);
    final choice = _choice ?? initial;
    final resName = {
          for (final r in ref.watch(resourcesProvider).value ?? const [])
            r.id: r.name,
        }[current.resourceId] ??
        current.resourceId;
    final gameMax = current.gameId == null
        ? null
        : ref.watch(gameByIdProvider(current.gameId!)).value?.maxLocalPlayers;

    final newCount = choice.count;
    final changed = _choice != null &&
        (newCount != current.controllerCount ||
            choice.padIds.toSet().difference(heldSet).isNotEmpty ||
            heldSet.difference(choice.padIds.toSet()).isNotEmpty);
    final actions = ref.watch(sessionActionsProvider);
    final before = actions.nextHourCost(
        widget.active.session, current, current.controllerCount);
    final after = newCount == null
        ? null
        : actions.nextHourCost(widget.active.session, current, newCount);
    final theme = Theme.of(context);
    final controllers = ref.watch(controllersProvider).value ?? const [];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Change controllers', style: theme.textTheme.titleLarge),
          Text(
            held.isEmpty
                ? 'Now ${current.controllerCount ?? 0} · pads not tracked yet'
                : 'Now ${held.length} · ${padLabels(held, controllers)}',
            key: const ValueKey('current-pads'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (!openAsync.hasValue)
            const Text('Checking controllers…')
          else
            ControllerChoiceField(
              resourceId: current.resourceId,
              resourceName: resName,
              choice: choice,
              keepIds: heldSet,
              exceptOccupantId: current.id,
              maxCount: gameMax,
              onChanged: (c) => setState(() => _choice = c),
            ),
          const SizedBox(height: AppSpacing.md),
          if (changed && before != null && after != null)
            Text(
              before == after
                  ? 'Next hour stays ${after.display}.'
                  : 'Next hour: ${before.display} → ${after.display}. '
                      'Time already played keeps its old rate.',
              key: const ValueKey('rate-change'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.arena.warning),
            )
          else
            Text(
              'A new segment starts now; the session timer is unchanged.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: !changed || _busy ? null : () => _apply(choice),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(ControllerChoice choice) async {
    setState(() => _busy = true);
    final r = await ref.read(sessionActionsProvider).changeControllers(
          session: widget.active.session,
          current: widget.active.current,
          controllers: choice,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    final n = choice.count ?? 0;
    r.fold(
      (_) {
        Navigator.of(context).pop();
        showToast(context, 'Now $n controller${n == 1 ? '' : 's'}');
      },
      (f) => showFailure(context, f),
    );
  }
}
