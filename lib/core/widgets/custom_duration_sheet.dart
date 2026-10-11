import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A fast, floor-friendly way to enter a custom number of minutes (spec §12).
///
/// Staff pick a duration that isn't one of the quick presets: step by ±5/±15 or
/// type an exact value. Returns the chosen minutes, or null if cancelled. The
/// caller recalculates its quote from the result (the pricing engine already
/// supports arbitrary durations — this only exposes it in the UI).
Future<int?> showCustomMinutesSheet(
  BuildContext context, {
  int? initial,
  String title = 'Custom duration',
  int min = 5,
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
  late final TextEditingController _controller =
      TextEditingController(text: '$_minutes');

  void _set(int value) {
    final clamped = value.clamp(widget.min, widget.max);
    setState(() => _minutes = clamped);
    if (_controller.text != '$clamped') {
      _controller.text = '$clamped';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  void _bump(int delta) => _set(_minutes + delta);

  @override
  void dispose() {
    _controller.dispose();
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
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Minutes',
                suffixText: 'min',
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null) setState(() => _minutes = n.clamp(widget.min, widget.max));
              },
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
