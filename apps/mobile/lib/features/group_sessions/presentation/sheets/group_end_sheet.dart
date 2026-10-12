import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ends and bills the whole group (group feature §9). Closes every open
/// assignment at the same instant and writes the final charges.
Future<void> showGroupEndSheet(BuildContext context, ActiveGroupSession group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupEndSheet(group: group),
  );
}

class _GroupEndSheet extends ConsumerStatefulWidget {
  const _GroupEndSheet({required this.group});
  final ActiveGroupSession group;

  @override
  ConsumerState<_GroupEndSheet> createState() => _GroupEndSheetState();
}

class _GroupEndSheetState extends ConsumerState<_GroupEndSheet> {
  bool _waive = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = ref.watch(groupSessionActionsProvider);
    final now = ref.watch(clockProvider).now();
    final bill = actions.endSummary(widget.group, at: now);

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
          Text('Bill group', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: theme.textTheme.bodyLarge),
              Text(_waive ? '₹0 (waived)' : bill.total.display,
                  style: AppTextStyles.amount(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('${widget.group.group.playerCount} players · '
              '${widget.group.group.billingMode.label}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          BorrowedPadsNotice(
            sessionRef: Controller.groupRef(widget.group.group.id),
            returning: _returning,
            onToggle: (id, on) => setState(
                () => on ? _returning.add(id) : _returning.remove(id)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark complimentary (waive)'),
            value: _waive,
            onChanged: (v) => setState(() => _waive = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: const Icon(Icons.check),
            label: Text(_busy ? 'Ending…' : 'End & bill'),
          ),
        ],
      ),
    );
  }

  /// Borrowed pads ticked as walked back; recorded once the group ends.
  final Set<String> _returning = {};

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final r = await ref
        .read(groupSessionActionsProvider)
        .end(widget.group, markWaived: _waive);
    if (r.isOk && _returning.isNotEmpty) {
      await returnPadsHome(ref, _returning);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) {
        Navigator.of(context).pop(); // close the sheet
        Navigator.of(context).maybePop(); // leave the detail screen
      },
      (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.display))),
    );
  }
}
