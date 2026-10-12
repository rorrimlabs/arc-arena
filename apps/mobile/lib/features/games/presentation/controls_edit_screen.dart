import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/features/games/presentation/widgets/button_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Edit the controls guide staff read out to a customer mid-session
/// (brief §5 "Game instructions and controls").
///
/// Controls are grouped into sections ("Attacking", "Defending") and each row
/// is an action plus the buttons that perform it. Buttons are stored as plain
/// tokens (`cross`, `l1`, `r2`) and rendered as PlayStation glyphs, so the
/// same guide reads correctly wherever it is shown.
class ControlsEditScreen extends ConsumerStatefulWidget {
  const ControlsEditScreen({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<ControlsEditScreen> createState() => _ControlsEditScreenState();
}

class _ControlsEditScreenState extends ConsumerState<ControlsEditScreen> {
  List<GameControl> _controls = const [];
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows =
        await ref.read(catalogRepositoryProvider).controlsFor(widget.game.id);
    if (mounted) {
      setState(() {
        _controls = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;

    // Preserve the order staff arranged them in.
    final bySection = <String, List<GameControl>>{};
    for (final c in _controls) {
      bySection.putIfAbsent(c.section, () => []).add(c);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.game.name} · controls'),
        actions: [
          TextButton(
            onPressed: _dirty && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRow(null),
        icon: const Icon(Icons.add),
        label: const Text('Add control'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
              children: [
                if (_controls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        Icon(Icons.gamepad_outlined,
                            size: 44, color: arena.textSubtle),
                        const SizedBox(height: AppSpacing.md),
                        Text('No controls yet',
                            style: ArenaType.h3.copyWith(color: arena.text)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Add the handful staff get asked about most — '
                          'shoot, pass, sprint, reload.',
                          textAlign: TextAlign.center,
                          style: ArenaType.caption
                              .copyWith(color: arena.textMuted),
                        ),
                      ],
                    ),
                  ),
                for (final entry in bySection.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                        top: AppSpacing.md, bottom: AppSpacing.xs),
                    child: Text(entry.key.toUpperCase(),
                        style:
                            ArenaType.overline.copyWith(color: arena.textMuted)),
                  ),
                  for (final c in entry.value)
                    Dismissible(
                      key: ValueKey(c.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.lg),
                        color: arena.danger,
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) => setState(() {
                        _controls = [..._controls]..removeWhere((x) => x.id == c.id);
                        _dirty = true;
                      }),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.action),
                        subtitle: c.explanation == null || c.explanation!.isEmpty
                            ? null
                            : Text(c.explanation!),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            for (final b in c.buttons) ButtonGlyph(b),
                          ],
                        ),
                        onTap: () => _editRow(c),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Future<void> _editRow(GameControl? existing) async {
    final sections = {for (final c in _controls) c.section}.toList()..sort();
    final result = await showModalBottomSheet<GameControl>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ControlEditor(
        gameId: widget.game.id,
        existing: existing,
        knownSections: sections,
        nextSortOrder: _controls.length,
      ),
    );
    if (result == null) return;
    setState(() {
      final next = [..._controls];
      final at = next.indexWhere((c) => c.id == result.id);
      if (at >= 0) {
        next[at] = result;
      } else {
        next.add(result);
      }
      _controls = next;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Re-number so the stored order matches what is on screen.
    final ordered = [
      for (var i = 0; i < _controls.length; i++)
        _controls[i].copyWith(sortOrder: i),
    ];
    await ref
        .read(catalogRepositoryProvider)
        .replaceControls(widget.game.id, ordered);
    ref.invalidate(gameControlsProvider(widget.game.id));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Controls saved for ${widget.game.name}.')),
    );
  }
}

class _ControlEditor extends StatefulWidget {
  const _ControlEditor({
    required this.gameId,
    required this.existing,
    required this.knownSections,
    required this.nextSortOrder,
  });

  final String gameId;
  final GameControl? existing;
  final List<String> knownSections;
  final int nextSortOrder;

  @override
  State<_ControlEditor> createState() => _ControlEditorState();
}

class _ControlEditorState extends State<_ControlEditor> {
  /// The PlayStation buttons staff actually cite, in controller order.
  static const _tokens = <String>[
    'CROSS', 'CIRCLE', 'SQUARE', 'TRIANGLE',
    'L1', 'L2', 'R1', 'R2',
    'DPAD_UP', 'DPAD_DOWN', 'DPAD_LEFT', 'DPAD_RIGHT',
    'L3', 'R3', 'OPTIONS', 'TOUCHPAD',
  ];

  late final TextEditingController _section = TextEditingController(
      text: widget.existing?.section ?? widget.knownSections.firstOrNull ?? '');
  late final TextEditingController _action =
      TextEditingController(text: widget.existing?.action ?? '');
  late final TextEditingController _explanation =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final List<String> _buttons = [...?widget.existing?.buttons];
  String? _error;

  @override
  void dispose() {
    _section.dispose();
    _action.dispose();
    _explanation.dispose();
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
            Text(widget.existing == null ? 'Add control' : 'Edit control',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _section,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Section',
                hintText: 'Attacking',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.knownSections.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final s in widget.knownSections)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => _section.text = s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _action,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Action',
                hintText: 'Shoot',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Buttons', style: theme.textTheme.labelLarge),
            Text(
              _buttons.isEmpty
                  ? 'Tap in the order they are pressed.'
                  : 'Press order: ${_buttons.join(' → ')}',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final t in _tokens)
                  InputChip(
                    avatar: ButtonGlyph(t),
                    label: Text(t.replaceAll('_', ' ')),
                    selected: _buttons.contains(t),
                    onPressed: () => setState(() {
                      // Tapping adds to the sequence; tapping a chosen one
                      // removes it, so a two-button combo is two taps.
                      _buttons.contains(t) ? _buttons.remove(t) : _buttons.add(t);
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _explanation,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Explanation (optional)',
                hintText: 'Hold for a power shot',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: arena.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  void _save() {
    final section = _section.text.trim();
    final action = _action.text.trim();
    if (section.isEmpty) {
      setState(() => _error = 'Give it a section, e.g. Attacking.');
      return;
    }
    if (action.isEmpty) {
      setState(() => _error = 'What does it do? e.g. Shoot.');
      return;
    }
    if (_buttons.isEmpty) {
      setState(() => _error = 'Pick at least one button.');
      return;
    }
    final explanation = _explanation.text.trim();
    Navigator.of(context).pop(
      GameControl(
        id: widget.existing?.id ?? const Uuid().v4(),
        gameId: widget.gameId,
        section: section,
        action: action,
        buttons: List.unmodifiable(_buttons),
        explanation: explanation.isEmpty ? null : explanation,
        notes: widget.existing?.notes,
        imageUrl: widget.existing?.imageUrl,
        sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
      ),
    );
  }
}
