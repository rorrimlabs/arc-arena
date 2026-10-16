import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/custom_duration_sheet.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/session_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extend an active session by +15/+30/+60 with validation + confirmation
/// (spec §13). Shows old end, new end, added time and added cost.
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
          Builder(builder: (context) {
            const presets = [15, 30, 60];
            final isCustom = !presets.contains(_minutes);
            return Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text('+$m min'),
                    selected: _minutes == m,
                    onSelected: (_) {
                      setState(() => _minutes = m);
                      _preview();
                    },
                  ),
                ChoiceChip(
                  label: Text(isCustom ? 'Custom · +$_minutes min' : 'Custom'),
                  selected: isCustom,
                  onSelected: (_) async {
                    final mins = await showCustomMinutesSheet(context,
                        initial: _minutes, title: 'Custom extension');
                    if (mins != null) {
                      setState(() => _minutes = mins);
                      _preview();
                    }
                  },
                ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (plan != null)
            _PlanDetails(plan: plan)
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

class _PlanDetails extends StatelessWidget {
  const _PlanDetails({required this.plan});
  final ExtensionPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(value, style: AppTextStyles.mono(theme.textTheme.bodyMedium!)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row('Current end', IstTime.format12(plan.oldEnd)),
          row('New end', IstTime.format12(plan.newEnd)),
          row('Added time', '+${plan.addedMinutes} min'),
          row('Added cost', plan.addedCost.display),
        ],
      ),
    );
  }
}
