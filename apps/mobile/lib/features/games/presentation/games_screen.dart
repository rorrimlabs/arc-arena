import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/router/app_nav.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/games/presentation/game_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The editable game library (spec §3). Disabled games stay visible here.
class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key});

  static const String path = '/games';

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  String _query = '';

  void _open(Game? game) {
    AppNav.to(context, GameEditScreen(game: game));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allGamesProvider).value ?? const [];
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all
            .where((g) =>
                g.name.toLowerCase().contains(q) ||
                g.aliases.any((a) => a.toLowerCase().contains(q)))
            .toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Game Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('Add game'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search game',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final g = list[i];
                return ListTile(
                  leading: Icon(
                    Icons.videogame_asset_outlined,
                    color: g.active ? null : theme.disabledColor,
                  ),
                  title: Text(
                    g.name,
                    style: g.active
                        ? null
                        : TextStyle(color: theme.disabledColor),
                  ),
                  subtitle: Text([
                    g.categoryName ?? '—',
                    PlayerMode.labelOf(g.playModes),
                    if (!g.active) 'Disabled',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(g),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
