import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/features/more/presentation/station_controllers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Manage the stations, tables and rooms the arena runs (brief §2).
///
/// The resource list is data, not code: adding a fifth PS5 or retiring a pool
/// table happens here and the floor, bookings, availability rules and reports
/// all follow, because every one of them reads the same table.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  static const String path = '/settings/stations';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final openSegments = ref.watch(openSegmentsProvider).value ?? const [];
    final groupOpen = ref.watch(openGroupAssignmentsProvider).value ?? const [];
    final busy = <String>{
      for (final s in openSegments) s.resourceId,
      for (final a in groupOpen) a.resourceId,
    };
    final controllers = ref.watch(controllersProvider).value ?? const <Controller>[];
    final noun = ref.watch(resourceNounProvider);
    // Types that use controllers: only their stations get a Controllers button.
    final padTypes = {
      for (final t in ref.watch(activitiesProvider).value ?? const <Activity>[])
        if (t.usesControllers) t.code,
    };

    return Scaffold(
      appBar: AppBar(title: Text(noun.many)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text('Add ${noun.word}'),
      ),
      body: resources.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  'No ${noun.many.toLowerCase()} yet. Add your first '
                  '${noun.word} to start running the floor.',
                  textAlign: TextAlign.center,
                  style: ArenaType.body.copyWith(color: arena.textMuted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
              children: [
                for (final r in resources)
                  _StationTile(
                    resource: r,
                    inUse: busy.contains(r.id),
                    usesControllers: r.activityCodes.any(padTypes.contains),
                    controllersHere: [
                      for (final c in controllers)
                        if (c.currentResourceId == r.id) c,
                    ],
                    onEdit: () => _edit(context, ref, r),
                    onStatus: (s) => _setStatus(context, ref, r, s),
                    onControllers: () => showStationControllersSheet(context, r),
                  ),
              ],
            ),
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    Resource r,
    ResourceStatus status,
  ) async {
    // Taking a station out of service while someone is on it would strand a
    // live session; the action refuses that with a reason.
    final result =
        await ref.read(catalogActionsProvider).setStationStatus(r, status);
    if (result.isOk) ref.invalidate(resourcesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.display ?? '${r.name}: ${status.label}.',
          ),
        ),
      );
    }
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, Resource? existing) async {
    final activities = ref.read(activitiesProvider).value ?? const [];
    final saved = await showModalBottomSheet<Resource>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StationEditor(
        existing: existing,
        activityOptions: [for (final a in activities) (code: a.code, name: a.name)],
      ),
    );
    if (saved == null) return;
    final result = await ref.read(catalogActionsProvider).saveStation(saved);
    if (result.isOk) ref.invalidate(resourcesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.failureOrNull?.display ?? '${saved.name} saved.'),
        ),
      );
    }
  }
}

class _StationTile extends StatelessWidget {
  const _StationTile({
    required this.resource,
    required this.inUse,
    required this.usesControllers,
    required this.controllersHere,
    required this.onEdit,
    required this.onStatus,
    required this.onControllers,
  });

  final Resource resource;
  final bool inUse;
  final bool usesControllers;
  final List<Controller> controllersHere;
  final VoidCallback onEdit;
  final ValueChanged<ResourceStatus> onStatus;
  final VoidCallback onControllers;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final (Color color, String label) = inUse
        ? (arena.stPlaying, 'In use')
        : switch (resource.status) {
            ResourceStatus.available => (arena.stFree, 'Available'),
            ResourceStatus.maintenance => (arena.stOos, 'Maintenance'),
            ResourceStatus.temporarilyUnavailable =>
              (arena.stOos, 'Unavailable'),
            ResourceStatus.disabled => (arena.textSubtle, 'Disabled'),
          };

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        resource.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ArenaType.label.copyWith(color: arena.text),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusDotLabel(label: label, color: color),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    resource.kind.label,
                    if (resource.activityCodes.isNotEmpty)
                      resource.activityCodes.join(' · '),
                  ].join(' — '),
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                if (controllersHere.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Builder(builder: (context) {
                    final usable =
                        controllersHere.where((c) => c.status.isUsable).length;
                    final short = usable < controllersHere.length;
                    return Text(
                      '$usable of ${controllersHere.length} controllers usable',
                      style: ArenaType.caption.copyWith(
                        color: short ? arena.warning : arena.textSubtle,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          // Shown for any controller-capable station (so the first pad can be
          // added), not only ones that already have pads.
          if (controllersHere.isNotEmpty || usesControllers)
            IconButton(
              tooltip: 'Controllers',
              icon: const Icon(Icons.videogame_asset_outlined),
              onPressed: onControllers,
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          PopupMenuButton<ResourceStatus>(
            tooltip: 'Set status',
            icon: const Icon(Icons.more_vert),
            onSelected: onStatus,
            itemBuilder: (_) => [
              for (final s in ResourceStatus.values)
                PopupMenuItem(
                  value: s,
                  enabled: s != resource.status,
                  child: Text(s.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StationEditor extends StatefulWidget {
  const _StationEditor({
    required this.existing,
    required this.activityOptions,
  });

  final Resource? existing;
  final List<({String code, String name})> activityOptions;

  @override
  State<_StationEditor> createState() => _StationEditorState();
}

class _StationEditorState extends State<_StationEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late ResourceKind _kind = widget.existing?.kind ?? ResourceKind.station;
  late ResourceStatus _status =
      widget.existing?.status ?? ResourceStatus.available;
  late final Set<String> _codes = {...?widget.existing?.activityCodes};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arena = context.arena;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(widget.existing == null ? 'Add station' : 'Edit station',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'HEX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final k in ResourceKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('What it can host', style: theme.textTheme.labelLarge),
            Text(
              'RIFT hosts PS5 and VR — it can never run both at once.',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final a in widget.activityOptions)
                  FilterChip(
                    label: Text(a.name),
                    selected: _codes.contains(a.code),
                    onSelected: (on) => setState(() {
                      on ? _codes.add(a.code) : _codes.remove(a.code);
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final s in ResourceStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: arena.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('Save station')),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the station a name.');
      return;
    }
    if (_codes.isEmpty) {
      setState(() => _error = 'Pick at least one activity it can host.');
      return;
    }
    Navigator.of(context).pop(
      Resource(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: name,
        kind: _kind,
        status: _status,
        sortOrder: widget.existing?.sortOrder ?? 99,
        activityCodes: _codes.toList(),
      ),
    );
  }
}
