import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A fast, floor-friendly way to enter a custom number of minutes (spec §12).
///
/// Staff pick a duration that isn't one of the quick presets: step by ±5/±15
/// minutes or ±1 hour, or type exact hours and minutes. Returns the chosen
/// total in minutes, or null if cancelled. The
/// caller recalculates its quote from the result (the pricing engine already
/// supports arbitrary durations — this only exposes it in the UI).
Future<int?> showCustomMinutesSheet(
  BuildContext context, {
  int? initial,
  String title = 'Custom duration',
  int min = 1,
  int max = 600,
  int step = 5,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _CustomMinutes(
        initial: initial,
        title: title,
        min: min,
        max: max,
        step: step,
      ),
    ),
  );
}

class _CustomMinutes extends StatefulWidget {
  const _CustomMinutes({
    required this.initial,
    required this.title,
    required this.min,
    required this.max,
    required this.step,
  });

  final int? initial;
  final String title;
  final int min;
  final int max;
  final int step;

  @override
  State<_CustomMinutes> createState() => _CustomMinutesState();
}

class _CustomMinutesState extends State<_CustomMinutes> {
  late int _minutes = (widget.initial ?? 60).clamp(widget.min, widget.max);
  late final TextEditingController _hours =
      TextEditingController(text: '${_minutes ~/ 60}');
  late final TextEditingController _mins =
      TextEditingController(text: '${_minutes % 60}');

  /// A stepper or the clamp moved the total: both fields follow it.
  void _set(int value) {
    final clamped = value.clamp(widget.min, widget.max);
    setState(() => _minutes = clamped);
    _write(_hours, clamped ~/ 60);
    _write(_mins, clamped % 60);
  }

  static void _write(TextEditingController c, int value) {
    if (c.text == '$value') return;
    c.text = '$value';
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  /// Typing in either field: the total is hours × 60 + minutes (minutes may
  /// run past 59, e.g. 0 h 90 min), clamped to the allowed range.
  void _typed() {
    final h = int.tryParse(_hours.text) ?? 0;
    final m = int.tryParse(_mins.text) ?? 0;
    setState(() => _minutes = (h * 60 + m).clamp(widget.min, widget.max));
  }

  void _bump(int delta) => _set(_minutes + delta);

  @override
  void dispose() {
    _hours.dispose();
    _mins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arena = context.arena;

    Widget stepButton(String label, int delta) => OutlinedButton(
          onPressed: () => _bump(delta),
          child: Text(label),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            // Live echo of the chosen length in h/m, so staff read it the way
            // they read every other timer in the app.
            Text(
              formatMinutesLabel(Duration(minutes: _minutes)),
              style: AppTextStyles.amount(context).copyWith(color: arena.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: stepButton('−15', -15)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: stepButton('−5', -5)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: stepButton('+5', 5)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: stepButton('+15', 15)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: stepButton('−1 h', -60)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: stepButton('+1 h', 60)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      suffixText: 'h',
                    ),
                    onChanged: (_) => _typed(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _mins,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      suffixText: 'min',
                    ),
                    onChanged: (_) => _typed(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_minutes),
              child: Text('Use ${formatMinutesLabel(Duration(minutes: _minutes))}'),
            ),
          ],
        ),
      ),
    );
  }
}
