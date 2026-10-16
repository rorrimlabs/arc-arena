import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
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
  final _waiveReasonCtrl = TextEditingController();

  @override
  void dispose() {
    _waiveReasonCtrl.dispose();
    super.dispose();
  }

  /// A waive writes money off: it is never recorded without a reason.
  bool get _waiveReasonMissing =>
      _waive && _waiveReasonCtrl.text.trim().isEmpty;

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
          if (_waive)
            TextField(
              key: const ValueKey('waive-reason'),
              controller: _waiveReasonCtrl,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Reason for waiving',
                helperText: 'The owner sees it with the amount written off',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _busy || _waiveReasonMissing ? null : _confirm,
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
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref
        .read(groupSessionActionsProvider)
        .end(widget.group,
            markWaived: _waive,
            waiveReason: _waive ? _waiveReasonCtrl.text : null);
    final notReturned = r.isOk && _returning.isNotEmpty
        ? _returning.length - await returnPadsHome(ref, _returning)
        : 0;
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) {
        final toast = AppToast.of(context);
        Navigator.of(context).pop(); // close the sheet
        Navigator.of(context).maybePop(); // leave the detail screen
        toast.show([
          _waive ? 'Group waived (complimentary).' : 'Group ended and billed.',
          if (notReturned > 0)
            '$notReturned pad${notReturned == 1 ? ' was' : 's were'} not marked '
                'returned; mark ${notReturned == 1 ? 'it' : 'them'} on the controller board.',
        ].join(' '));
      },
      (f) => showFailure(context, f),
    );
  }
}
