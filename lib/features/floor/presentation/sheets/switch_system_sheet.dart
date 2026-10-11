import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Switch the current segment to another system (spec §10). Shows only systems
/// that are available, operational, support the current activity, and can run
/// the current game (spec §24–§25). The game and controller count carry over;
/// staff pick which pads at the new system the players take (optional — the
/// pads at the old system stay there and are released at the switch instant).
Future<void> showSwitchSystemSheet(BuildContext context, ActiveSession active) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SwitchSheet(active: active),
  );
}

class _SwitchSheet extends ConsumerStatefulWidget {
  const _SwitchSheet({required this.active});
  final ActiveSession active;

  @override
  ConsumerState<_SwitchSheet> createState() => _SwitchSheetState();
}

class _SwitchSheetState extends ConsumerState<_SwitchSheet> {
  Resource? _target;
  ControllerChoice _choice = ControllerChoice.none;
  bool _busy = false;

  ActiveSession get active => widget.active;

  @override
  Widget build(BuildContext context) {
    final current = active.current;
    final resources = ref.watch(resourcesProvider).value ?? const [];
    final open = ref.watch(openSegmentsProvider).value ?? const [];
    final busy = {for (final s in open) s.resourceId};

    // Compatibility: if a game is set, only systems that can run it.
    final compat = current.gameId == null
        ? null
        : {
            for (final rf in ref.watch(resourcesForGameProvider(current.gameId!)).value ?? [])
              rf.resource.id: rf.status,
          };

    final candidates = resources.where((r) {
      if (r.id == current.resourceId) return false;
      if (r.status != ResourceStatus.available) return false;
      if (!r.activityCodes.contains(current.activityCode)) return false;
      if (busy.contains(r.id)) return false;
      if (r.currentMode != null && r.currentMode != current.activityCode) {
        return false;
      }
      if (compat != null && !(compat[r.id]?.isPlayable ?? false)) return false;
      return true;
    }).toList();

    final count = current.controllerCount ?? 1;
    final held = <String>{
      for (final a in ref.watch(openPadAllocationsProvider).value ?? const [])
        if (a.segmentId == current.id) a.controllerId,
    };
    final gameMax = current.gameId == null
        ? null
        : ref.watch(gameByIdProvider(current.gameId!)).value?.maxLocalPlayers;
    // Scrolls: a station list plus the pad picker can outgrow a phone sheet.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Switch system', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('No compatible system is free right now.'),
            )
          else
            for (final r in candidates)
              ListTile(
                leading: const Icon(Icons.desktop_windows_outlined),
                title: Text(r.name),
                subtitle: Text(current.activityCode),
                selected: _target?.id == r.id,
                trailing: Icon(_target?.id == r.id
                    ? Icons.check_circle
                    : Icons.swap_horiz),
                // Same count at the new system; the field picks that many free
                // pads there (the session's own pads can be carried over).
                onTap: () => setState(() {
                  _target = r;
                  _choice = ControllerChoice.tracked(requested: count);
                }),
              ),
          if (_target != null &&
              (ref.watch(activitiesProvider).value ?? const [])
                  .any((a) => a.code == current.activityCode && a.usesControllers)) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Controllers at ${_target!.name}',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            ControllerChoiceField(
              resourceId: _target!.id,
              resourceName: _target!.name,
              choice: _choice,
              keepIds: held,
              exceptOccupantId: current.id,
              maxCount: gameMax,
              onChanged: (c) => setState(() => _choice = c),
            ),
          ],
          if (_target != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _busy ? null : () => _switch(_target!),
              icon: const Icon(Icons.swap_horiz),
              label: Text('Switch to ${_target!.name}'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _switch(Resource target) async {
    setState(() => _busy = true);
    final r = await ref.read(sessionActionsProvider).switchSystem(
          session: active.session,
          current: active.current,
          resourceId: target.id,
          resourceName: target.name,
          activityCode: active.current.activityCode,
          gameId: active.current.gameId,
          controllers: _choice.requested == null
              ? ControllerChoice.count(active.current.controllerCount)
              : _choice,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Switched to ${target.name}')));
      },
      (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.display))),
    );
  }
}
