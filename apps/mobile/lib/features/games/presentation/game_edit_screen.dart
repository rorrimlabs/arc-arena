import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/games/presentation/controls_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Add or edit a game, including its per-system compatibility (spec §3–§4).
class GameEditScreen extends ConsumerStatefulWidget {
  const GameEditScreen({super.key, this.game, this.initialName});
  final Game? game;

  /// Prefills the name when adding a new game (e.g. from a picker search that
  /// found nothing), so staff don't retype what they just searched.
  final String? initialName;

  @override
  ConsumerState<GameEditScreen> createState() => _GameEditScreenState();
}

class _GameEditScreenState extends ConsumerState<GameEditScreen> {
  static const _uuid = Uuid();

  late final String _id;
  late final TextEditingController _nameCtrl;
  String? _categoryId;
  final Set<String> _platforms = {};
  PlayerMode _playerMode = PlayerMode.single;
  int _maxPlayers = 1;
  bool _active = true;

  List<Resource> _resources = const [];
  final Map<String, GameAvailability> _compat = {};
  bool _loading = true;
  bool _saving = false;

  bool get _isNew => widget.game == null;

  @override
  void initState() {
    super.initState();
    final g = widget.game;
    _id = g?.id ?? _uuid.v4();
    _nameCtrl = TextEditingController(text: g?.name ?? widget.initialName ?? '');
    _categoryId = g?.categoryId;
    _platforms.addAll(g?.platforms ?? const ['PS5']);
    _playerMode = g?.playerMode ?? PlayerMode.single;
    _maxPlayers = g?.maxLocalPlayers ?? 1;
    _active = g?.active ?? true;
    _load();
  }

  Future<void> _load() async {
    final catalog = ref.read(catalogRepositoryProvider);
    _resources = await catalog.resources();
    if (!_isNew) {
      for (final rf in await catalog.resourcesForGame(_id)) {
        _compat[rf.resource.id] = rf.status;
      }
    }
    for (final r in _resources) {
      _compat.putIfAbsent(r.id, () => GameAvailability.notInstalled);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(gameCategoriesProvider).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add game' : 'Edit game')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Platform', style: theme.textTheme.labelLarge),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final p in ['PS5', 'PSVR2'])
                      FilterChip(
                        label: Text(p),
                        selected: _platforms.contains(p),
                        onSelected: (s) => setState(() =>
                            s ? _platforms.add(p) : _platforms.remove(p)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<PlayerMode>(
                  initialValue: _playerMode,
                  decoration: const InputDecoration(
                    labelText: 'Player mode',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in PlayerMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (v) => setState(() {
                    _playerMode = v ?? _playerMode;
                    if (!_playerMode.isMultiplayer) _maxPlayers = 1;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_playerMode.isMultiplayer)
                  DropdownButtonFormField<int>(
                    initialValue: _maxPlayers.clamp(1, 8),
                    decoration: const InputDecoration(
                      labelText: 'Max local players',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final n in [1, 2, 3, 4, 5, 6, 7, 8])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) => setState(() => _maxPlayers = v ?? _maxPlayers),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Disabled games stay in history but drop out of pickers'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                const Divider(),
                Text('Compatibility', style: theme.textTheme.titleMedium),
                Text('Which systems can run this game (spec §4)',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                for (final r in _resources)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.name)),
                        DropdownButton<GameAvailability>(
                          value: _compat[r.id],
                          items: [
                            for (final s in GameAvailability.values)
                              DropdownMenuItem(value: s, child: Text(s.label)),
                          ],
                          onChanged: (v) => setState(
                              () => _compat[r.id] = v ?? _compat[r.id]!),
                        ),
                      ],
                    ),
                  ),
                if (!_isNew) ...[
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ControlsEditScreen(game: widget.game!),
                      ),
                    ),
                    icon: const Icon(Icons.gamepad_outlined),
                    label: const Text('Controls guide'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    setState(() => _saving = true);
    final saved = await ref.read(catalogActionsProvider).saveGame(
          Game(
            id: _id,
            name: name,
            // Fields this form does not edit keep their stored values (aliases
            // are set on the admin dashboard).
            aliases: widget.game?.aliases ?? const [],
            lastPlayedAt: widget.game?.lastPlayedAt,
            categoryId: _categoryId,
            platforms: _platforms.toList(),
            playerMode: _playerMode,
            maxLocalPlayers: _maxPlayers,
            active: _active,
          ),
          compatibility: Map.of(_compat),
        );
    if (saved.isErr) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved.failureOrNull!.display)),
      );
      return;
    }
    // Refresh dependent views.
    ref.invalidate(allGamesProvider);
    ref.invalidate(activeGamesProvider);
    for (final r in _resources) {
      ref.invalidate(gamesForResourceProvider(r.id));
    }
    ref.invalidate(resourcesForGameProvider(_id));
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $name')));
    }
  }
}
