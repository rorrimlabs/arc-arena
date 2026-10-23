import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/custom_duration_sheet.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/session_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extend an active session by any number of minutes (slider in 5-min steps,
/// or typed) with validation + confirmation (spec §13). Shows old end, new
/// end, added time and added cost.
Future<void> showExtendSheet(BuildContext context, ActiveSession active) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ExtendSheet(active: active),
  );
}

class _ExtendSheet extends ConsumerStatefulWidget {
  const _ExtendSheet({required this.active});
  final ActiveSession active;
  @override
  ConsumerState<_ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends ConsumerState<_ExtendSheet> {
  int _minutes = 30;
  Result<ExtensionPlan>? _plan;
  bool _loading = false;
  bool _applying = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  Future<void> _preview() async {
    final token = ++_token;
    setState(() => _loading = true);
    final p = await ref.read(sessionActionsProvider).previewExtension(
        widget.active.session, widget.active.segments, _minutes);
    if (!mounted || token != _token) return;
    setState(() {
      _plan = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan?.valueOrNull;
    final failure = _plan?.failureOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Extend session', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          ExtendMinutesPicker(
            minutes: _minutes,
            onChanged: (m) => setState(() => _minutes = m),
            onDone: _set,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (plan != null)
            ExtensionSummary(
              oldEnd: plan.oldEnd,
              newEnd: plan.newEnd,
              addedMinutes: plan.addedMinutes,
              current: ref
                  .read(sessionActionsProvider)
                  .endSummary(widget.active.session, widget.active.segments,
                      at: plan.oldEnd)
                  .total,
              added: plan.addedCost,
            )
          else if (failure != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                failure.display,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: plan == null || _applying ? null : _apply,
            child: Text(_applying ? 'Extending…' : 'Confirm extension'),
          ),
        ],
      ),
    );
  }

  void _set(int minutes) {
    if (minutes < 1) return;
    setState(() => _minutes = minutes);
    _preview();
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final r = await ref.read(sessionActionsProvider)
        .extend(widget.active.session, widget.active.segments, _minutes);
    if (!mounted) return;
    setState(() => _applying = false);
    r.fold(
      (_) {
        Navigator.of(context).pop();
        showToast(context, 'Extended by $_minutes min');
      },
      (f) => showFailure(context, f),
    );
  }
}

/// Minutes to extend by: − / + and a slider in 1-min steps up to 4 h, or tap the figure to type any number. [onChanged] follows the slider as it moves;
/// [onDone] is the settled value (to preview).
class ExtendMinutesPicker extends StatelessWidget {
  const ExtendMinutesPicker({
    super.key,
    required this.minutes,
    required this.onChanged,
    required this.onDone,
  });

  static const _min = 1;
  static const _max = 240;

  final int minutes;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: '1 min less',
              onPressed: minutes > _min ? () => onDone(minutes - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: TextButton(
                key: const ValueKey('extend-minutes'),
                onPressed: () async {
                  final mins = await showCustomMinutesSheet(context,
                      initial: minutes, title: 'Extend by');
                  if (mins != null && mins > 0) onDone(mins);
                },
                child: Text('+$minutes min', style: theme.textTheme.headlineSmall),
              ),
            ),
            IconButton.outlined(
              tooltip: '1 min more',
              onPressed: () => onDone(minutes + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          min: _min.toDouble(),
          max: _max.toDouble(),
          divisions: _max - _min,
          value: minutes.clamp(_min, _max).toDouble(),
          label: '+$minutes min',
          onChanged: (v) => onChanged(v.round()),
          onChangeEnd: (v) => onDone(v.round()),
        ),
      ],
    );
  }
}

/// What staff read out before extending: the time, and the bill so far plus
/// the extension's price giving the new total.
class ExtensionSummary extends StatelessWidget {
  const ExtensionSummary({
    super.key,
    required this.oldEnd,
    required this.newEnd,
    required this.addedMinutes,
    required this.current,
    required this.added,
  });

  final DateTime oldEnd;
  final DateTime newEnd;
  final int addedMinutes;
  final Paise current;
  final Paise added;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: strong
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium),
              Text(value,
                  style: strong
                      ? AppTextStyles.amount(context)
                      : AppTextStyles.mono(theme.textTheme.bodyMedium!)),
            ],
          ),
        );
    return Container(
      key: const ValueKey('extend-summary'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row('Ends', '${IstTime.format12(oldEnd)} → ${IstTime.format12(newEnd)}'),
          const Divider(),
          row('Bill so far (to ${IstTime.format12(oldEnd)})', current.display),
          row('Extension +$addedMinutes min', '+${added.display}'),
          const Divider(),
          row('New total', (current + added).display, strong: true),
        ],
      ),
    );
  }
}
