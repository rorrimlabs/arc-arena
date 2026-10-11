import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Record a payment against the group (group feature §9). Amounts are entered in
/// rupees and stored in paise.
Future<void> showGroupPaymentSheet(
    BuildContext context, ActiveGroupSession group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupPaymentSheet(group: group),
  );
}

class _GroupPaymentSheet extends ConsumerStatefulWidget {
  const _GroupPaymentSheet({required this.group});
  final ActiveGroupSession group;

  @override
  ConsumerState<_GroupPaymentSheet> createState() => _GroupPaymentSheetState();
}

class _GroupPaymentSheetState extends ConsumerState<_GroupPaymentSheet> {
  final _controller = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Record payment', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              prefixText: '₹ ',
              labelText: 'Amount',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(
                  label: Text(m.name.toUpperCase()),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final rupees = double.tryParse(_controller.text.trim());
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount.')));
      return;
    }
    setState(() => _busy = true);
    final r = await ref.read(groupSessionActionsProvider).recordPayment(
          RecordGroupPaymentCommand(
            groupId: widget.group.group.id,
            amountPaise: (rupees * 100).round(),
            method: _method,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (_) => Navigator.of(context).pop(),
      (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.display))),
    );
  }
}
