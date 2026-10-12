import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extend the whole group's shared window (group feature §8). Every active
/// assignment's remaining time moves together because they all read the
/// parent's end.
Future<void> showGroupExtendSheet(
    BuildContext context, ActiveGroupSession group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupExtendSheet(group: group),
  );
}

class _GroupExtendSheet extends ConsumerStatefulWidget {
  const _GroupExtendSheet({required this.group});
  final ActiveGroupSession group;

  @override
  ConsumerState<_GroupExtendSheet> createState() => _GroupExtendSheetState();
}

class _GroupExtendSheetState extends ConsumerState<_GroupExtendSheet> {
  int _minutes = 30;
  Result<GroupExtensionPlan>? _preview;
  bool _loading = false;
  bool _busy = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  Future<void> _recompute() async {
    final token = ++_token;
    setState(() => _loading = true);
    final p = await ref
        .read(groupSessionActionsProvider)
        .previewExtension(widget.group, _minutes);
    if (!mounted || token != _token) return;
    setState(() {
      _preview = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _preview?.valueOrNull;
    final failure = _preview?.failureOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Extend group', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final m in [15, 30, 60])
                ChoiceChip(
                  label: Text('+$m min'),
                  selected: _minutes == m,
                  onSelected: (_) {
                    setState(() => _minutes = m);
                    _recompute();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Text('Checking…')
          else if (plan != null)
            Text(
              'New end ${IstTime.format12(plan.newEnd)} · '
              'adds ${plan.addedCost.display}',
              style: AppTextStyles.mono(theme.textTheme.bodyMedium!),
            )
          else if (failure != null)
            Text(failure.display,
                style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: plan == null || _busy ? null : _confirm,
            child: const Text('Extend'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final r = await ref
        .read(groupSessionActionsProvider)
        .extend(widget.group, _minutes);
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) => Navigator.of(context).pop(),
      (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.display))),
    );
  }
}
