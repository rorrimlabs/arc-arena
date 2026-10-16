import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:arena_ops/features/new_session/presentation/game_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Switch a player to another system, or add a player to one (group feature §5).
/// Only compatible, operational, free systems are offered; the repository
/// re-validates on confirm.
Future<void> showGroupAssignSheet(
  BuildContext context, {
  required ActiveGroupSession group,
  required int playerNumber,
  required bool isSwitch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupAssignSheet(
      group: group,
      playerNumber: playerNumber,
      isSwitch: isSwitch,
    ),
  );
}

class _GroupAssignSheet extends ConsumerStatefulWidget {
  const _GroupAssignSheet({
    required this.group,
    required this.playerNumber,
    required this.isSwitch,
  });
  final ActiveGroupSession group;
  final int playerNumber;
  final bool isSwitch;

  @override
  ConsumerState<_GroupAssignSheet> createState() => _GroupAssignSheetState();
}

class _GroupAssignSheetState extends ConsumerState<_GroupAssignSheet> {
  /// The station type the group plays on: the one its players were placed on
  /// (a group is created with at least one placement), whatever code the
  /// owner gave it.
  String get _activity => widget.group.assignments.first.activityCode;
  Resource? _resource;
  String? _gameId;
  String? _gameName;
  int? _gameMax;
  ControllerChoice _choice = const ControllerChoice.tracked(requested: 1);
  bool _busy = false;

  /// The live pre-flight for the current system / game / controllers: null
  /// while checking or nothing picked yet; Ok enables the button.
  Result<void>? _check;
  int _checkToken = 0;

  Future<void> _recheck() async {
    final r = _resource;
    if (r == null) return;
    final token = ++_checkToken;
    final result =
        await ref.read(groupSessionActionsProvider).previewAssignment(
              group: widget.group.group,
              playerNumber: widget.playerNumber,
              resourceId: r.id,
              resourceName: r.name,
              activityCode: _activity,
              gameId: _gameId,
              controllers: _choice,
              current: widget.isSwitch ? _current : null,
            );
    if (!mounted || token != _checkToken) return;
    setState(() => _check = result);
  }

  void _changed(VoidCallback f) {
    setState(() {
      f();
      _check = null;
    });
    _recheck();
  }

  // Computed once: which systems this player may use. Checked for ONE
  // controller — more can be borrowed, which the controller field explains —
  // so picking pads never re-queries (or flashes) the list.
  Future<List<Resource>>? _candidates;

  GroupAssignment? get _current =>
      widget.group.currentForPlayer(widget.playerNumber);

  /// Pads other players in this group hold right now, labelled for the picker.
  Map<String, String> _padsOfOthers() => {
        for (final a in ref.watch(openPadAllocationsProvider).value ?? const [])
          if (a.groupId == widget.group.group.id &&
              a.playerNumber != widget.playerNumber)
            a.controllerId: 'Player ${a.playerNumber}',
      };

  @override
  Widget build(BuildContext context) {
    final actions = ref.watch(groupSessionActionsProvider);
    _candidates ??= actions.candidateResources(
      group: widget.group.group,
      playerNumber: widget.playerNumber,
      activityCode: _activity,
    );
    final held = <String>{
      for (final a in ref.watch(openPadAllocationsProvider).value ?? const [])
        if (_current != null && a.assignmentId == _current!.id) a.controllerId,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSwitch
                ? 'Switch Player ${widget.playerNumber}'
                : 'Add Player ${widget.playerNumber}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('System', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<Resource>>(
            future: _candidates,
            builder: (context, snap) {
              final list = snap.data ?? const <Resource>[];
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text('Checking systems…'),
                );
              }
              if (list.isEmpty) {
                return const Text('No compatible system is free right now.');
              }
              return Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final r in list)
                    ChoiceChip(
                      label: Text(r.name),
                      selected: _resource?.id == r.id,
                      onSelected: (_) => _changed(() {
                        _resource = r;
                        _gameId = null;
                        _gameName = null;
                        _gameMax = null;
                        // Same requested count; pads re-picked at this system.
                        _choice = ControllerChoice.tracked(
                            requested: _choice.requested ?? 1);
                      }),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _resource == null
                ? null
                : () async {
                    final g = await showGamePicker(context,
                        resourceId: _resource!.id, resourceName: _resource!.name);
                    if (g != null) {
                      _changed(() {
                        _gameId = g.id;
                        _gameName = g.name;
                        _gameMax = g.maxLocalPlayers;
                      });
                    }
                  },
            icon: const Icon(Icons.videogame_asset_outlined),
            label: Text(_gameName ??
                (_resource == null ? 'Pick a system first' : 'Select game')),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Controllers', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          if (_resource == null)
            Text('Pick a system first.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            ControllerChoiceField(
              resourceId: _resource!.id,
              resourceName: _resource!.name,
              choice: _choice,
              keepIds: held,
              pickedForOthers: _padsOfOthers(),
              exceptOccupantId: _current?.id,
              maxCount: _gameMax,
              onChanged: (c) => _changed(() => _choice = c),
            ),
          if (_check?.failureOrNull != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _check!.failureOrNull!.display,
              key: const ValueKey('assign-problem'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            // Enabled only once the live pre-flight has passed.
            onPressed: _resource == null || _busy || !(_check?.isOk ?? false)
                ? null
                : _confirm,
            child: Text(widget.isSwitch ? 'Switch' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final actions = ref.read(groupSessionActionsProvider);
    final Result result = widget.isSwitch
        ? await actions.switchSystem(
            groupId: widget.group.group.id,
            playerNumber: widget.playerNumber,
            resourceId: _resource!.id,
            resourceName: _resource!.name,
            activityCode: _activity,
            gameId: _gameId,
            controllers: _choice,
            current: _current,
          )
        : await actions.addPlayer(
            groupId: widget.group.group.id,
            playerNumber: widget.playerNumber,
            resourceId: _resource!.id,
            resourceName: _resource!.name,
            activityCode: _activity,
            gameId: _gameId,
            controllers: _choice,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (_) {
        showToast(
          context,
          widget.isSwitch
              ? 'Player ${widget.playerNumber} switched to ${_resource!.name}'
              : 'Player ${widget.playerNumber} added to ${_resource!.name}',
        );
        Navigator.of(context).pop();
      },
      (f) => showFailure(context, f),
    );
  }
}

/// Change the game for a player's current system (group feature §6).
Future<void> showGroupChangeGameSheet(
  BuildContext context, {
  required ActiveGroupSession group,
  required GroupAssignment current,
}) async {
  final game = await showGamePicker(
    context,
    resourceId: current.resourceId,
    resourceName: current.resourceId,
  );
  if (game == null) return;
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context);
  final r = await container.read(groupSessionActionsProvider).changeGame(
        groupId: group.group.id,
        current: current,
        gameId: game.id,
      );
  if (!context.mounted) return;
  r.fold(
    (_) => showToast(context, 'Now playing ${game.name}'),
    (f) => showFailure(context, f),
  );
}

/// Change the controller count — and which pads — for a player's current
/// system (group feature §6, allocation brief §8). The pads the player holds
/// start out picked; the group's shared timer is untouched.
Future<void> showGroupChangeControllersSheet(
  BuildContext context, {
  required ActiveGroupSession group,
  required GroupAssignment current,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupChangeControllersSheet(group: group, current: current),
  );
}

class _GroupChangeControllersSheet extends ConsumerStatefulWidget {
  const _GroupChangeControllersSheet({required this.group, required this.current});
  final ActiveGroupSession group;
  final GroupAssignment current;

  @override
  ConsumerState<_GroupChangeControllersSheet> createState() =>
      _GroupChangeControllersSheetState();
}

class _GroupChangeControllersSheetState
    extends ConsumerState<_GroupChangeControllersSheet> {
  ControllerChoice? _choice;
  bool _busy = false;
  Result<void>? _check;
  int _checkToken = 0;

  Future<void> _recheck(ControllerChoice choice) async {
    final token = ++_checkToken;
    final current = widget.current;
    final names = {
      for (final r in ref.read(resourcesProvider).value ?? const []) r.id: r.name,
    };
    final result =
        await ref.read(groupSessionActionsProvider).previewAssignment(
              group: widget.group.group,
              playerNumber: current.playerNumber,
              resourceId: current.resourceId,
              resourceName: names[current.resourceId] ?? current.resourceId,
              activityCode: current.activityCode,
              gameId: current.gameId,
              controllers: choice,
              current: current,
            );
    if (!mounted || token != _checkToken) return;
    setState(() => _check = result);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final open = ref.watch(openPadAllocationsProvider).value ?? const [];
    final held = <String>[
      for (final a in open)
        if (a.assignmentId == current.id) a.controllerId,
    ];
    final others = <String, String>{
      for (final a in open)
        if (a.groupId == widget.group.group.id &&
            a.playerNumber != current.playerNumber)
          a.controllerId: 'Player ${a.playerNumber}',
    };
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
    final changed = _choice != null &&
        (choice.count != current.controllerCount ||
            choice.padIds.toSet().difference(heldSet).isNotEmpty ||
            heldSet.difference(choice.padIds.toSet()).isNotEmpty);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Controllers · Player ${current.playerNumber}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          ControllerChoiceField(
            resourceId: current.resourceId,
            resourceName: resName,
            choice: choice,
            keepIds: heldSet,
            pickedForOthers: others,
            exceptOccupantId: current.id,
            maxCount: current.gameId == null
                ? null
                : ref
                    .watch(gameByIdProvider(current.gameId!))
                    .value
                    ?.maxLocalPlayers,
            onChanged: (c) {
              setState(() {
                _choice = c;
                _check = null;
              });
              _recheck(c);
            },
          ),
          if (changed && _check?.failureOrNull != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _check!.failureOrNull!.display,
              key: const ValueKey('assign-problem'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('From now on only — earlier time keeps its controllers.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: !changed || _busy || !(_check?.isOk ?? false)
                ? null
                : () => _apply(choice),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(ControllerChoice choice) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(groupSessionActionsProvider).changeControllers(
          groupId: widget.group.group.id,
          current: widget.current,
          controllers: choice,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) {
        showToast(context, 'Controllers updated');
        Navigator.of(context).pop();
      },
      (f) => showFailure(context, f),
    );
  }
}
