import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The controllers physically at one station — the owner's inventory surface.
///
/// A pad with stick drift gets marked faulty here, and from that moment no
/// session can start on it and no other station can borrow it. The owner can
/// also rename a pad, add one, set its home station, and move/borrow it to
/// another station. A pad away from home says where it belongs, so it can be
/// walked back. For a dual-capability station (RIFT) the owner locks PS5 or VR
/// here — disabled while a session is running on it.
Future<void> showStationControllersSheet(
  BuildContext context,
  Resource resource,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _StationControllersSheet(resource: resource),
    ),
  );
}

class _StationControllersSheet extends ConsumerWidget {
  const _StationControllersSheet({required this.resource});

  final Resource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final theme = Theme.of(context);
    final all = ref.watch(controllersProvider).value ?? const <Controller>[];
    // The live view of this station: it may have been renamed/mode-changed.
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final station = resources.firstWhere(
      (r) => r.id == resource.id,
      orElse: () => resource,
    );

    final here = [
      for (final c in all)
        if (c.currentResourceId == station.id) c,
    ]..sort((a, b) => a.label.compareTo(b.label));
    final usable = here.where((c) => c.status.isUsable).length;

    // Pads that belong here but are sitting somewhere else — the other half of
    // "where did HEX-2 go?".
    final away = [
      for (final c in all)
        if (c.homeResourceId == station.id && c.currentResourceId != station.id)
          c,
    ]..sort((a, b) => a.label.compareTo(b.label));

    final names = {for (final r in resources) r.id: r.name};

    // A station is "busy" when it has an open single segment or group
    // assignment — the same set the stations screen uses. Only the RIFT mode
    // lock is gated on it; moving a pad is deliberately allowed while busy.
    final busy = <String>{
      for (final s in ref.watch(openSegmentsProvider).value ?? const [])
        s.resourceId,
      for (final a in ref.watch(openGroupAssignmentsProvider).value ?? const [])
        a.resourceId,
    };
    final occupied = busy.contains(station.id);
    final dual =
        station.activityCodes.contains('PS5') &&
        station.activityCodes.contains('VR');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${station.name} controllers',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      here.isEmpty
                          ? 'No controllers at this station.'
                          : '$usable of ${here.length} usable',
                      style: ArenaType.caption.copyWith(
                        color: usable == here.length
                            ? arena.textMuted
                            : arena.warning,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Add controller',
                icon: const Icon(Icons.add),
                onPressed: () => _addController(context, ref, station),
              ),
            ],
          ),
          if (dual) ...[
            const SizedBox(height: AppSpacing.md),
            _ModeSelector(
              station: station,
              occupied: occupied,
              onSelect: (code) => _setMode(context, ref, station, code),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView(
              children: [
                for (final c in here)
                  _ControllerRow(
                    key: ValueKey(c.id),
                    controller: c,
                    homeName: names[c.homeResourceId] ?? c.homeResourceId,
                    atHomeStation: station.id,
                    onStatus: (s, note) => _setStatus(context, ref, c, s, note),
                    onRename: () => _rename(context, ref, c),
                    onSetHome: () => _setHome(context, ref, c, station),
                    onMove: () => _move(context, ref, c, station),
                    onSendHome: () => _returnHome(context, ref, c),
                  ),
                if (away.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'BELONGS HERE, CURRENTLY ELSEWHERE',
                    style: ArenaType.overline.copyWith(color: arena.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final c in away)
                    ListTile(
                      key: ValueKey('away-${c.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.north_east, color: arena.textSubtle),
                      title: Text(c.label),
                      subtitle: Text(
                        'At ${names[c.currentResourceId] ?? c.currentResourceId}'
                        '${c.isOnLoan ? ' · on loan' : ''}',
                      ),
                      trailing: TextButton(
                        onPressed: () => _returnHome(context, ref, c),
                        child: const Text('Return home'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shows what happened: [done] on success, otherwise the refusal.
  void _report(ScaffoldMessengerState m, Result<Object?> r, String done) =>
      m.showSnackBar(SnackBar(content: Text(r.failureOrNull?.display ?? done)));

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    Controller c,
    ControllerStatus status,
    String? note,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final r = await ref
        .read(catalogActionsProvider)
        .setControllerStatus(c.id, status, notes: note);
    _report(m, r, '${c.label}: ${status.label.toLowerCase()}.');
  }

  Future<void> _addController(
    BuildContext context,
    WidgetRef ref,
    Resource station,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final label = await _textPrompt(
      context,
      title: 'Add controller to ${station.name}',
      hint: '${station.name}-3',
      confirm: 'Add',
    );
    if (label == null || label.isEmpty) return;
    final r = await ref
        .read(catalogActionsProvider)
        .addController(label: label, resourceId: station.id);
    _report(m, r, 'Added $label to ${station.name}.');
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Controller c,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final label = await _textPrompt(
      context,
      title: 'Rename ${c.label}',
      initial: c.label,
      confirm: 'Rename',
    );
    if (label == null || label.isEmpty || label == c.label) return;
    final r = await ref.read(catalogActionsProvider).renameController(c, label);
    _report(m, r, 'Renamed to $label.');
  }

  Future<void> _setHome(
    BuildContext context,
    WidgetRef ref,
    Controller c,
    Resource station,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final dest = await _pickStation(
      context,
      ref,
      title: 'Home station for ${c.label}',
      exclude: c.homeResourceId,
    );
    if (dest == null) return;
    final r = await ref
        .read(catalogActionsProvider)
        .setControllerHome(c, dest.id);
    _report(m, r, '${c.label} now belongs to ${dest.name}.');
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    Controller c,
    Resource station,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final choice = await _pickMove(context, ref, c);
    if (choice == null) return;
    final r = await ref
        .read(catalogActionsProvider)
        .moveController(
          controller: c,
          toResourceId: choice.$1.id,
          kind: choice.$2,
        );
    _report(m, r, 'Moved ${c.label} to ${choice.$1.name}.');
  }

  Future<void> _returnHome(
    BuildContext context,
    WidgetRef ref,
    Controller c,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final r = await ref.read(catalogActionsProvider).returnHome(c);
    _report(m, r, 'Recalled ${c.label}.');
  }

  Future<void> _setMode(
    BuildContext context,
    WidgetRef ref,
    Resource station,
    String? code,
  ) async {
    final m = ScaffoldMessenger.of(context);
    final r = await ref
        .read(catalogActionsProvider)
        .setStationMode(station.id, code);
    if (r.isOk) ref.invalidate(resourcesProvider);
    _report(m, r, '${station.name} set to ${code ?? 'either mode'}.');
  }

  Future<String?> _textPrompt(
    BuildContext context, {
    required String title,
    String? hint,
    String? initial,
    required String confirm,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      confirm: confirm,
    ),
  );

  Future<Resource?> _pickStation(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    String? exclude,
  }) {
    final stations = [
      for (final r in ref.read(resourcesProvider).value ?? const <Resource>[])
        if (r.id != exclude) r,
    ];
    return showModalBottomSheet<Resource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final r in stations)
              ListTile(
                key: ValueKey('pick-${r.id}'),
                title: Text(r.name),
                onTap: () => Navigator.of(context).pop(r),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Future<(Resource, ControllerMoveKind)?> _pickMove(
    BuildContext context,
    WidgetRef ref,
    Controller c,
  ) {
    final stations = [
      for (final r in ref.read(resourcesProvider).value ?? const <Resource>[])
        if (r.id != c.currentResourceId) r,
    ];
    return showModalBottomSheet<(Resource, ControllerMoveKind)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _MoveSheet(controllerLabel: c.label, destinations: stations),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.station,
    required this.occupied,
    required this.onSelect,
  });

  final Resource station;
  final bool occupied;
  final void Function(String? code) onSelect;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    // One chip per hosted activity, plus "Either" to clear the lock.
    final options = <(String?, String)>[
      for (final code in station.activityCodes) (code, code),
      (null, 'Either'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MODE',
          style: ArenaType.overline.copyWith(color: arena.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (code, label) in options)
              ChoiceChip(
                label: Text(label),
                selected: station.currentMode == code,
                onSelected: occupied ? null : (_) => onSelect(code),
              ),
          ],
        ),
        if (occupied)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'End the current session to change mode.',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ),
      ],
    );
  }
}

class _ControllerRow extends StatelessWidget {
  const _ControllerRow({
    super.key,
    required this.controller,
    required this.homeName,
    required this.atHomeStation,
    required this.onStatus,
    required this.onRename,
    required this.onSetHome,
    required this.onMove,
    required this.onSendHome,
  });

  final Controller controller;
  final String homeName;
  final String atHomeStation;
  final void Function(ControllerStatus, String?) onStatus;
  final VoidCallback onRename;
  final VoidCallback onSetHome;
  final VoidCallback onMove;
  final VoidCallback onSendHome;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final c = controller;
    // A pad standing at this station but belonging to another can be walked back.
    final canSendHome =
        c.homeResourceId != atHomeStation &&
        c.currentResourceId == atHomeStation;
    final (Color color, String label) = switch (c.status) {
      ControllerStatus.usable => (arena.primary, 'Usable'),
      ControllerStatus.faulty => (arena.danger, 'Faulty'),
      ControllerStatus.missing => (arena.warning, 'Missing'),
      ControllerStatus.retired => (arena.textSubtle, 'Retired'),
      ControllerStatus.unavailable => (arena.textSubtle, 'Unavailable'),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.videogame_asset_outlined,
        color: c.status.isUsable ? arena.text : arena.textSubtle,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.label,
              style: ArenaType.label.copyWith(color: arena.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusDotLabel(label: label, color: color),
        ],
      ),
      subtitle: Text(
        [
          if (c.isAwayFromHome) 'Home: $homeName',
          if (c.isOnLoan) 'on loan',
          if (c.notes != null && c.notes!.isNotEmpty) c.notes!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Manage',
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  onRename();
                case 'home':
                  onSetHome();
                case 'move':
                  onMove();
                case 'sendhome':
                  onSendHome();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(
                value: 'home',
                child: Text('Set home station'),
              ),
              const PopupMenuItem(value: 'move', child: Text('Move / borrow')),
              if (canSendHome)
                const PopupMenuItem(
                  value: 'sendhome',
                  child: Text('Send home'),
                ),
            ],
          ),
          PopupMenuButton<ControllerStatus>(
            tooltip: 'Set status',
            icon: const Icon(Icons.more_vert),
            onSelected: (s) async {
              // A fault is worth a note; the other states rarely are.
              if (s == ControllerStatus.faulty) {
                final note = await _askNote(context, c.label);
                if (note == null) return; // cancelled
                onStatus(s, note.isEmpty ? null : note);
              } else {
                onStatus(s, null);
              }
            },
            itemBuilder: (_) => [
              for (final s in ControllerStatus.values)
                PopupMenuItem(
                  value: s,
                  enabled: s != c.status,
                  child: Text(s.label),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String?> _askNote(BuildContext context, String label) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TextPromptDialog(
          title: '$label is faulty',
          hint: 'Left stick drift',
          confirm: 'Mark faulty',
        ),
      );
}

/// Destination + kind picker for moving/borrowing a pad. returnHome is its own
/// action (Send home / Return home), so this offers loan and permanent only.
class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.controllerLabel, required this.destinations});

  final String controllerLabel;
  final List<Resource> destinations;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  Resource? _dest;
  ControllerMoveKind _kind = ControllerMoveKind.loan;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Move ${widget.controllerLabel}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'TO STATION',
              style: ArenaType.overline.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in widget.destinations)
                  ChoiceChip(
                    label: Text(r.name),
                    selected: _dest?.id == r.id,
                    onSelected: (_) => setState(() => _dest = r),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'HOW',
              style: ArenaType.overline.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final k in const [
                  ControllerMoveKind.loan,
                  ControllerMoveKind.permanent,
                ])
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _dest == null
                  ? null
                  : () => Navigator.of(context).pop((_dest!, _kind)),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A free-text prompt: the fault note, a rename, or a new controller's label.
/// Owns its own controller so nothing disposes it mid route-animation.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    this.hint,
    this.initial,
    required this.confirm,
  });

  final String title;
  final String? hint;
  final String? initial;
  final String confirm;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
