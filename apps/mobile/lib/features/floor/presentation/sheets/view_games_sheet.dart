import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/games/presentation/controls_sheet.dart';
import 'package:arena_ops/features/new_session/presentation/new_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which games are playable on a system, before starting a session (spec §5).
///
/// Availability is **per system**, so this is also where staff fix it: a disc
/// that stopped working on GHOST is marked there and nowhere else, with a note
/// saying why. Opens the game's controls too, and starts a session.
Future<void> showViewGamesSheet(BuildContext context, Resource resource) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _ViewGamesSheet(resource: resource),
    ),
  );
}

class _ViewGamesSheet extends ConsumerWidget {
  const _ViewGamesSheet({required this.resource});
  final Resource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final theme = Theme.of(context);
    final games =
        ref.watch(gamesForResourceProvider(resource.id)).value ?? const [];
    // Playable first, then the rest alphabetically.
    final sorted = [...games]..sort((a, b) {
        if (a.status.isPlayable == b.status.isPlayable) {
          return a.game.name.compareTo(b.game.name);
        }
        return a.status.isPlayable ? -1 : 1;
      });
    final playable = sorted.where((g) => g.status.isPlayable).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(resource.name, style: theme.textTheme.titleLarge),
          Text(
            '$playable of ${sorted.length} games playable on this system',
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text(
                      'No active games in the library yet.',
                      style: ArenaType.body.copyWith(color: arena.textMuted),
                    ),
                  )
                : ListView(
                    children: [
                      for (final g in sorted)
                        _GameRow(
                          resource: resource,
                          game: g.game,
                          status: g.status,
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: FilledButton.icon(
              onPressed: resource.status.isBookable
                  ? () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NewSessionScreen(initialResource: resource),
                      ));
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text('Start session on ${resource.name}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameRow extends ConsumerWidget {
  const _GameRow({
    required this.resource,
    required this.game,
    required this.status,
  });

  final Resource resource;
  final Game game;
  final GameAvailability status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        status.isPlayable ? Icons.check_circle : Icons.cancel_outlined,
        color: status.isPlayable ? arena.primary : arena.textSubtle,
      ),
      title: Text(game.name),
      subtitle: Text(
        '${game.playerMode.label}'
        '${game.playerMode.isMultiplayer ? ' · up to ${game.maxLocalPlayers}' : ''}'
        '${status.isPlayable ? '' : ' · ${status.label}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Controls',
            icon: const Icon(Icons.sports_esports_outlined),
            onPressed: () => showControlsSheet(context, game.id),
          ),
          IconButton(
            tooltip: 'Set status on ${resource.name}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editStatus(context, ref),
          ),
        ],
      ),
      onTap: () => _editStatus(context, ref),
      textColor: status.isPlayable ? null : theme.disabledColor,
    );
  }

  Future<void> _editStatus(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<({GameAvailability s, String? n})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StatusEditor(
        gameName: game.name,
        resourceName: resource.name,
        initial: status,
      ),
    );
    if (result == null) return;
    await ref.read(catalogRepositoryProvider).setCompatibility(
          game.id,
          resource.id,
          result.s,
          notes: result.n,
        );
    ref.invalidate(gamesForResourceProvider(resource.id));
    ref.invalidate(resourcesForGameProvider(game.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${game.name} on ${resource.name}: ${result.s.label}.',
          ),
        ),
      );
    }
  }
}

class _StatusEditor extends StatefulWidget {
  const _StatusEditor({
    required this.gameName,
    required this.resourceName,
    required this.initial,
  });

  final String gameName;
  final String resourceName;
  final GameAvailability initial;

  @override
  State<_StatusEditor> createState() => _StatusEditorState();
}

class _StatusEditorState extends State<_StatusEditor> {
  late GameAvailability _status = widget.initial;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.gameName, style: theme.textTheme.titleLarge),
            Text(
              'Status on ${widget.resourceName} only',
              style: ArenaType.caption.copyWith(color: context.arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<GameAvailability>(
              groupValue: _status,
              onChanged: (v) => setState(() => _status = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in GameAvailability.values)
                    RadioListTile<GameAvailability>(
                      contentPadding: EdgeInsets.zero,
                      value: s,
                      title: Text(s.label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Disc scratched · needs reinstall',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                (
                  s: _status,
                  n: _notes.text.trim().isEmpty ? null : _notes.text.trim()
                ),
              ),
              child: const Text('Save status'),
            ),
          ],
        ),
      ),
    );
  }
}
