import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_segmented.dart';
import 'package:arena_ops/core/widgets/custom_duration_sheet.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/services/group_activity.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:arena_ops/features/group_sessions/presentation/group_detail_screen.dart';
import 'package:arena_ops/features/new_session/presentation/customer_picker_sheet.dart';
import 'package:arena_ops/features/new_session/presentation/game_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the party is allocated to systems (group feature §2).
enum _Alloc { oneSystem, separate }

/// Create a group session: one primary customer, several players and
/// controllers, one shared duration, allocated either to one shared console or
/// to separate consoles (group feature §1–§2) of the arena's console station
/// type (groupActivityCode). Pushed from the Floor FAB.
class GroupSessionScreen extends ConsumerStatefulWidget {
  const GroupSessionScreen({super.key, this.initialResource});

  /// Optionally preselect a station the staff tapped on the floor.
  final Resource? initialResource;

  @override
  ConsumerState<GroupSessionScreen> createState() => _GroupSessionScreenState();
}

class _GroupSessionScreenState extends ConsumerState<GroupSessionScreen> {
  /// The station type this group plays on (groupActivityCode): null until the
  /// catalog is read, or when the arena has no type with controllers and games.
  String? _activity;

  /// The tapped station was considered for one-system mode (once, after the
  /// catalog arrived).
  bool _preselected = false;

  Customer? _customer;
  int _playerCount = 3;
  int _controllers = 3;
  int _duration = 60;
  bool _openEnded = false;
  _Alloc _alloc = _Alloc.separate;

  // One-system mode.
  String? _sharedResId;
  String? _sharedResName;
  String? _sharedGameId;
  String? _sharedGameName;

  /// One-system mode: one pad per player, in the order picked — the first
  /// goes to Player 1, the second to Player 2, and so on.
  ControllerChoice _shared = ControllerChoice.none;

  // Separate mode: per-player choices keyed by player number.
  final Map<int, GroupPlayerDraft> _perPlayer = {};

  Result<GroupStartPlan>? _preview;
  bool _loadingPreview = false;
  bool _starting = false;
  int _token = 0;

  /// Resolves the group's station type from the catalog, and on the first
  /// pass preselects the tapped station when it offers that type.
  void _resolveActivity(List<Activity> activities) {
    final r = widget.initialResource;
    _activity = groupActivityCode(activities, prefer: r?.activityCodes ?? const []);
    if (_preselected || _activity == null) return;
    _preselected = true;
    if (r != null && r.activityCodes.contains(_activity)) {
      _alloc = _Alloc.oneSystem;
      _sharedResId = r.id;
      _sharedResName = r.name;
    }
  }

  GroupPlayerDraft _player(int n) =>
      _perPlayer[n] ?? GroupPlayerDraft(playerNumber: n);

  GroupSessionDraft _assemble() {
    final players = <GroupPlayerDraft>[];
    for (var n = 1; n <= _playerCount; n++) {
      if (_alloc == _Alloc.oneSystem) {
        players.add(GroupPlayerDraft(
          playerNumber: n,
          resourceId: _sharedResId,
          resourceName: _sharedResName,
          activityCode: _sharedResId == null ? null : _activity,
          gameId: _sharedGameId,
          gameName: _sharedGameName,
          controllers: _sharedFor(n),
        ));
      } else {
        players.add(_player(n));
      }
    }
    // With an inventory the purchased count IS the pads picked — one source of
    // truth; the stepper only exists for an untracked (count-only) arena.
    final purchased = _tracked
        ? players.fold<int>(0, (n, p) => n + (p.controllerCount ?? 0))
        : _controllers;
    return GroupSessionDraft(
      primaryCustomerId: _customer?.id,
      playerCount: _playerCount,
      purchasedControllerCount: purchased < 1 ? 1 : purchased,
      durationMinutes: _openEnded ? null : _duration,
      openEnded: _openEnded,
      players: players,
    );
  }

  void _changed() {
    setState(() {});
    _recompute();
  }

  int? _gameMax(String? gameId) {
    if (gameId == null) return null;
    for (final g in ref.read(allGamesProvider).value ?? const []) {
      if (g.id == gameId) return g.maxLocalPlayers;
    }
    return null;
  }

  String? _gameMaxReason(GroupPlayerDraft p) {
    final max = _gameMax(p.gameId);
    if (max == null || max >= 4) return null;
    return '${p.gameName ?? 'This game'} supports up to $max local '
        'player${max == 1 ? '' : 's'} per system.';
  }

  /// Whether the arena tracks physical pads (any pad on the books).
  bool get _tracked => (ref.read(controllersProvider).value ?? const [])
      .any((c) => c.status != ControllerStatus.retired);

  /// Player [n]'s share of the one-system pick: their own pad (borrowed if
  /// it is elsewhere), or an unmet single-pad request.
  ControllerChoice _sharedFor(int n) {
    if (!_shared.isTracked) return const ControllerChoice.count(1);
    if (n > _shared.padIds.length) {
      return const ControllerChoice.tracked(requested: 1);
    }
    final id = _shared.padIds[n - 1];
    return ControllerChoice.tracked(
      requested: 1,
      padIds: [id],
      borrowIds: _shared.borrowIds.contains(id) ? {id} : const {},
    );
  }

  /// One-system pads are handed out one per player, so a short pick is said
  /// plainly for the whole party rather than per player.
  Failure? get _sharedPadsIncomplete =>
      _alloc == _Alloc.oneSystem && _shared.isTracked && _shared.shortfall > 0
          ? Failure(
              message: 'Picked ${_shared.padIds.length} of $_playerCount '
                  'controllers — one per player.',
              fix: 'Borrow ${_shared.shortfall} from another station, or '
                  'reduce players.',
              code: 'controllers_unavailable',
            )
          : null;

  /// Pads already picked by EARLIER players, labelled for the picker. Only
  /// lower-numbered players block player [n]: if two players' fields re-fit in
  /// the same frame they would otherwise keep swapping the same pad. Taking a
  /// later player's pad makes THAT player re-fit to another (or show a
  /// shortfall) — deterministic, and the same order previewCreate checks in.
  Map<String, String> _padsOfOthers(int n) => {
        for (var m = 1; m < n; m++)
          for (final id in _player(m).controllerIds) id: 'Player $m',
      };

  Future<void> _recompute() async {
    final token = ++_token;
    final incomplete = _sharedPadsIncomplete;
    if (incomplete != null) {
      setState(() {
        _preview = Err(incomplete);
        _loadingPreview = false;
      });
      return;
    }
    setState(() => _loadingPreview = true);
    final preview =
        await ref.read(groupSessionActionsProvider).previewCreate(_assemble());
    if (!mounted || token != _token) return;
    setState(() {
      _preview = preview;
      _loadingPreview = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activitiesProvider).value;
    if (activities == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New Group Session')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _resolveActivity(activities);
    if (_activity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New Group Session')),
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Group sessions need a station type that uses controllers and '
            'games. The owner adds one on the admin dashboard (Pricing), with '
            'stations that offer it.',
          ),
        ),
      );
    }
    // Watched so [_tracked] (read in helpers) is live and the screen rebuilds
    // when the inventory loads or changes.
    ref.watch(controllersProvider);
    ref.watch(allGamesProvider); // game limits for the per-player fields
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final openSegments = ref.watch(openSegmentsProvider).value ?? const [];
    final openGroup = ref.watch(openGroupAssignmentsProvider).value ?? const [];
    final occupied = <String>{
      for (final s in openSegments) s.resourceId,
      for (final a in openGroup) a.resourceId,
    };

    final stations = resources
        .where((r) =>
            r.activityCodes.contains(_activity) &&
            r.status == ResourceStatus.available &&
            (r.currentMode == null || r.currentMode == _activity))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New Group Session')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Section(
            title: '1 · Primary customer',
            child: OutlinedButton.icon(
              onPressed: () async {
                final c = await showCustomerPicker(context);
                if (c != null) {
                  _customer = c;
                  _changed();
                }
              },
              icon: const Icon(Icons.person_outline),
              label: Text(_customer?.displayName ?? 'Select customer'),
            ),
          ),
          _Section(
            title: '2 · Players',
            child: _Stepper(
              value: _playerCount,
              min: 1,
              max: 8,
              onChanged: (v) {
                _playerCount = v;
                if (_controllers < v) _controllers = v;
                _changed();
              },
            ),
          ),
          _Section(
            title: _tracked ? '3 · Controllers' : '3 · Controllers purchased',
            child: _tracked
                ? Text(
                    '${_assemble().purchasedControllerCount} in total — from '
                    'the controllers picked for each player below.',
                    key: const ValueKey('group-controller-total'),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : _Stepper(
                    value: _controllers,
                    min: 1,
                    max: 8,
                    onChanged: (v) {
                      _controllers = v;
                      _changed();
                    },
                  ),
          ),
          _Section(
            title: '4 · Duration',
            child: _DurationChips(
              presets: ref.watch(startPresetsProvider),
              duration: _duration,
              openEnded: _openEnded,
              onPreset: (d) {
                _duration = d;
                _openEnded = false;
                _changed();
              },
              onCustom: () async {
                final mins =
                    await showCustomMinutesSheet(context, initial: _duration);
                if (mins != null) {
                  _duration = mins;
                  _openEnded = false;
                  _changed();
                }
              },
              onOpen: () {
                _openEnded = true;
                _changed();
              },
            ),
          ),
          _Section(
            title: '5 · Allocation',
            child: ArenaSegmented<_Alloc>(
              value: _alloc,
              segments: const [
                ArenaSegment(_Alloc.oneSystem, 'One system'),
                ArenaSegment(_Alloc.separate, 'Separate systems'),
              ],
              onChanged: (v) {
                _alloc = v;
                _changed();
              },
            ),
          ),
          if (_alloc == _Alloc.oneSystem)
            _OneSystemPicker(
              stations: stations,
              occupied: occupied,
              resourceId: _sharedResId,
              gameName: _sharedGameName,
              onResource: (r) {
                _sharedResId = r.id;
                _sharedResName = r.name;
                _sharedGameId = null;
                _sharedGameName = null;
                _shared = _keepBorrows(_shared);
                _changed();
              },
              padPicker: _sharedResId == null
                  ? null
                  : ControllerChoiceField(
                      resourceId: _sharedResId!,
                      resourceName: _sharedResName ?? _sharedResId!,
                      choice: _shared,
                      fixedCount: _playerCount,
                      onChanged: (c) {
                        _shared = c;
                        _changed();
                      },
                    ),
              onPickGame: _sharedResId == null
                  ? null
                  : () async {
                      final g = await showGamePicker(context,
                          resourceId: _sharedResId!,
                          resourceName: _sharedResName);
                      if (g != null) {
                        _sharedGameId = g.id;
                        _sharedGameName = g.name;
                        _changed();
                      }
                    },
            )
          else
            for (var n = 1; n <= _playerCount; n++)
              _PlayerPicker(
                playerNumber: n,
                stations: stations,
                occupied: occupied,
                draft: _player(n),
                onResource: (r) {
                  _perPlayer[n] = _player(n).copyWith(
                    resourceId: r.id,
                    resourceName: r.name,
                    activityCode: _activity,
                    controllers: _keepBorrows(_player(n).controllers,
                        fallback: 1),
                    clearGame: true,
                  );
                  _changed();
                },
                padPicker: _player(n).resourceId == null
                    ? null
                    : ControllerChoiceField(
                        resourceId: _player(n).resourceId!,
                        resourceName: _player(n).resourceName ??
                            _player(n).resourceId!,
                        choice: _player(n).controllers,
                        pickedForOthers: _padsOfOthers(n),
                        // This player's game caps their controllers; teammates
                        // sharing the station are checked in the preview.
                        maxCount: _gameMax(_player(n).gameId),
                        maxReason: _gameMaxReason(_player(n)),
                        onChanged: (c) {
                          _perPlayer[n] = _player(n).copyWith(controllers: c);
                          _changed();
                        },
                      ),
                onPickGame: _player(n).resourceId == null
                    ? null
                    : () async {
                        final g = await showGamePicker(context,
                            resourceId: _player(n).resourceId!,
                            resourceName: _player(n).resourceName);
                        if (g != null) {
                          _perPlayer[n] = _player(n)
                              .copyWith(gameId: g.id, gameName: g.name);
                          _changed();
                        }
                      },
              ),
          // Room for the estimate bar (with per-system lines) to sit over.
          const SizedBox(height: 280),
        ],
      ),
      bottomSheet: _PreviewBar(
        preview: _preview,
        loading: _loadingPreview,
        starting: _starting,
        onStart: _start,
      ),
    );
  }

  /// A new station keeps the requested count and explicitly borrowed pads;
  /// pads picked at the previous station drop out (the field tops up again).
  ControllerChoice _keepBorrows(ControllerChoice c, {int? fallback}) {
    if (!c.isTracked) return ControllerChoice.count(c.requested ?? fallback);
    final borrowed = [
      for (final id in c.padIds)
        if (c.borrowIds.contains(id)) id,
    ];
    return ControllerChoice.tracked(
        requested: c.requested ?? fallback,
        padIds: borrowed,
        borrowIds: borrowed.toSet());
  }

  Future<void> _start() async {
    final incomplete = _sharedPadsIncomplete;
    if (incomplete != null) {
      showFailure(context, incomplete);
      return;
    }
    setState(() => _starting = true);
    final r = await ref.read(groupSessionActionsProvider).create(_assemble());
    if (!mounted) return;
    setState(() => _starting = false);
    r.fold(
      (group) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: group.id),
        ));
        showToast(context, 'Started group · ${_customer?.displayName ?? ''}');
      },
      (failure) => showFailure(context, failure),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
          child: Center(
            child: Text('$value',
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        IconButton.outlined(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _DurationChips extends StatelessWidget {
  const _DurationChips({
    required this.presets,
    required this.duration,
    required this.openEnded,
    required this.onPreset,
    required this.onCustom,
    required this.onOpen,
  });
  /// The arena's start durations (floor options).
  final List<int> presets;
  final int duration;
  final bool openEnded;
  final ValueChanged<int> onPreset;
  final VoidCallback onCustom;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isCustom = !openEnded && !presets.contains(duration);
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final d in presets)
          ChoiceChip(
            label: Text('$d min'),
            selected: !openEnded && duration == d,
            onSelected: (_) => onPreset(d),
          ),
        ChoiceChip(
          label: Text(isCustom
              ? 'Custom · ${formatMinutesLabel(Duration(minutes: duration))}'
              : 'Custom'),
          selected: isCustom,
          onSelected: (_) => onCustom(),
        ),
        ChoiceChip(
          label: const Text('Open'),
          selected: openEnded,
          onSelected: (_) => onOpen(),
        ),
      ],
    );
  }
}

class _OneSystemPicker extends StatelessWidget {
  const _OneSystemPicker({
    required this.stations,
    required this.occupied,
    required this.resourceId,
    required this.gameName,
    required this.onResource,
    required this.onPickGame,
    this.padPicker,
  });
  final List<Resource> stations;
  final Set<String> occupied;
  final String? resourceId;
  final String? gameName;
  final ValueChanged<Resource> onResource;
  final VoidCallback? onPickGame;

  /// Which pads, one per player in order (null until a system is picked).
  final Widget? padPicker;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '6 · Shared system',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final r in stations)
                ChoiceChip(
                  label: Text(r.name),
                  selected: resourceId == r.id,
                  onSelected: occupied.contains(r.id) && resourceId != r.id
                      ? null
                      : (_) => onResource(r),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onPickGame,
            icon: const Icon(Icons.videogame_asset_outlined),
            label: Text(gameName ??
                (resourceId == null ? 'Pick a system first' : 'Select game')),
          ),
          if (padPicker != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Controllers · one per player, in order',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            padPicker!,
          ],
        ],
      ),
    );
  }
}

class _PlayerPicker extends StatelessWidget {
  const _PlayerPicker({
    required this.playerNumber,
    required this.stations,
    required this.occupied,
    required this.draft,
    required this.onResource,
    required this.onPickGame,
    this.padPicker,
  });
  final int playerNumber;
  final List<Resource> stations;
  final Set<String> occupied;
  final GroupPlayerDraft draft;
  final ValueChanged<Resource> onResource;
  final VoidCallback? onPickGame;
  /// How many / which pads this player takes (null until a system is picked).
  final Widget? padPicker;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Player $playerNumber',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final r in stations)
                ChoiceChip(
                  label: Text(r.name),
                  selected: draft.resourceId == r.id,
                  // A player may share a system another player in this group
                  // already picked, so only single/other-group occupancy here
                  // disables a chip.
                  onSelected: occupied.contains(r.id) && draft.resourceId != r.id
                      ? null
                      : (_) => onResource(r),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onPickGame,
            icon: const Icon(Icons.videogame_asset_outlined),
            label: Text(draft.gameName ??
                (draft.resourceId == null
                    ? 'Pick a system first'
                    : 'Select game')),
          ),
          if (padPicker != null) ...[
            const SizedBox(height: AppSpacing.sm),
            padPicker!,
          ],
        ],
      ),
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({
    required this.preview,
    required this.loading,
    required this.starting,
    required this.onStart,
  });
  final Result<GroupStartPlan>? preview;
  final bool loading;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = preview?.valueOrNull;
    final failure = preview?.failureOrNull;
    final canStart = plan != null && !starting;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading)
                const Text('Calculating price…')
              else if (plan != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${IstTime.format12(plan.startedAt)} → '
                          '${plan.openEnded ? 'close' : IstTime.format12(plan.scheduledEndAt)}',
                          style:
                              AppTextStyles.mono(theme.textTheme.bodyMedium!),
                        ),
                        Text(plan.estimate.display,
                            key: const ValueKey('group-estimate'),
                            style: AppTextStyles.amount(context)),
                      ],
                    ),
                    // Each system is billed on its own and the lines are
                    // summed (cash rounding once, on the total).
                    for (final l in plan.lines)
                      Text(
                        '${l.label}'
                        '${l.controllerCount == null ? '' : ' · ${l.controllerCount} ctrl'}'
                        ' · ${formatMinutesLabel(Duration(minutes: l.minutes))}'
                        ' = ${l.amount.display}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                )
              else if (failure != null)
                Text(failure.display,
                    style: TextStyle(color: theme.colorScheme.error))
              else
                const Text('Pick a customer and assign players to systems.'),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: canStart ? onStart : null,
                icon: starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.groups),
                label: Text(starting ? 'Starting…' : 'Start group'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
