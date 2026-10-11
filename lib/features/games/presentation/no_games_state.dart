import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/features/games/presentation/game_edit_screen.dart';
import 'package:arena_ops/features/games/presentation/games_screen.dart';
import 'package:flutter/material.dart';

/// Opens the game library (add / edit games and their per-system compatibility).
void openGameLibrary(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const GamesScreen()));
}

/// Opens the add-game form, optionally prefilled with a searched name.
void openAddGame(BuildContext context, {String? name}) {
  final trimmed = name?.trim();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GameEditScreen(
        initialName: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      ),
    ),
  );
}

/// Shared empty state for the game pickers (new session + change game): instead
/// of a dead end, offer to add the game (with the searched name) or open the
/// library to set which systems run it and its player count (spec §3–§6).
class NoGamesState extends StatelessWidget {
  const NoGamesState({
    super.key,
    required this.resourceName,
    this.query = '',
    required this.onAdd,
    required this.onLibrary,
  });

  final String resourceName;
  final String query;
  final VoidCallback onAdd;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videogame_asset_off_outlined,
                color: arena.textSubtle, size: 36),
            const SizedBox(height: AppSpacing.md),
            Text(
              query.isEmpty
                  ? 'No playable games on $resourceName'
                  : 'No match for "$query" on $resourceName',
              textAlign: TextAlign.center,
              style: ArenaType.h3.copyWith(color: arena.text, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add it to the library, or open a game to set which systems run '
              'it and its player count.',
              textAlign: TextAlign.center,
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(query.isEmpty ? 'Add a game' : 'Add "$query"'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onLibrary,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Open game library'),
            ),
          ],
        ),
      ),
    );
  }
}
