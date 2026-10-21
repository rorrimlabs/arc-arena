import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/features/games/presentation/widgets/button_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the controls guide for a game in a bottom sheet (spec §23).
Future<void> showControlsSheet(BuildContext context, String gameId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _ControlsSheet(gameId: gameId),
    ),
  );
}

class _ControlsSheet extends ConsumerWidget {
  const _ControlsSheet({required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameByIdProvider(gameId)).value;
    final controls = ref.watch(gameControlsProvider(gameId)).value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            game?.name ?? 'Controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controls == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (controls.isEmpty)
            const Expanded(child: _NoControls())
          else
            Expanded(child: _ControlsList(controls: controls)),
        ],
      ),
    );
  }
}

class _NoControls extends StatelessWidget {
  const _NoControls();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gamepad_outlined, size: 48),
          const SizedBox(height: 8),
          const Text('Controls not added yet.'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'Add them in More → Settings → Games & controls → this game → '
              'Controls guide.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsList extends StatelessWidget {
  const _ControlsList({required this.controls});
  final List<GameControl> controls;

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<GameControl>>{};
    for (final c in controls) {
      sections.putIfAbsent(c.section, () => []).add(c);
    }
    final theme = Theme.of(context);

    return ListView(
      children: [
        for (final entry in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
            child: Text(
              entry.key,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final c in entry.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.action, style: theme.textTheme.bodyLarge),
                        if (c.explanation != null)
                          Text(c.explanation!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [for (final b in c.buttons) ButtonGlyph(b)],
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
