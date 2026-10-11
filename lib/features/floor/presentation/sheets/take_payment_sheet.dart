import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/payment.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Record a payment against a session — **before** it ends (a customer paying
/// up front), **during** it, or **after** it to settle an outstanding balance
/// (brief §10).
///
/// Payments are append-only: each tap writes one transaction with its own
/// method, amount and timestamp, so "₹200 UPI + ₹80 cash" is two rows that sum
/// to ₹280. Nothing here overwrites an earlier payment; a correction is a
/// refund row with a reason.
Future<void> showTakePaymentSheet(BuildContext context, Session session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _TakePaymentSheet(session: session),
    ),
  );
}

class _TakePaymentSheet extends ConsumerStatefulWidget {
  const _TakePaymentSheet({required this.session});
  final Session session;

  @override
  ConsumerState<_TakePaymentSheet> createState() => _TakePaymentSheetState();
}

class _TakePaymentSheetState extends ConsumerState<_TakePaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _enteredPaise =>
      ((double.tryParse(_amountCtrl.text.trim()) ?? 0) * 100).round();

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final theme = Theme.of(context);
    final session = widget.session;
    final payments =
        ref.watch(paymentsForSessionProvider(session.id)).value ?? const <Payment>[];
    final collected = payments.fold<int>(0, (sum, p) => sum + p.amountPaise);

    // A running session has no final bill yet, so settle against the live
    // estimate; a finished one has its stored, immutable billed amount.
    final billed = session.billedAmountPaise;
    final isFinal = billed != null;
    final target = billed ?? _liveEstimate();
    final remaining = target - collected;

    // Prefill with what is still owed, once, so staff usually just tap Record.
    if (!_prefilled) {
      _prefilled = true;
      if (remaining > 0) {
        _amountCtrl.text = (remaining / 100).toStringAsFixed(2);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Record payment', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isFinal
                  ? 'Final bill · settle the balance'
                  : 'Session is still running — this is the estimate so far',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            _Totals(
              billed: target,
              collected: collected,
              remaining: remaining,
              isEstimate: !isFinal,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Method', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(_methodLabel(m)),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Reference / note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Already recorded', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        p.isRefund ? Icons.undo : Icons.check_circle_outline,
                        size: 16,
                        color: p.isRefund ? arena.danger : arena.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${_methodLabel(p.method)} · '
                          '${IstTime.format12(p.createdAt)}'
                          '${p.note == null || p.note!.isEmpty ? '' : ' · ${p.note}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ArenaType.caption.copyWith(color: arena.textMuted),
                        ),
                      ),
                      Text(
                        Paise(p.amountPaise).display,
                        style: AppTextStyles.mono(ArenaType.caption)
                            .copyWith(color: arena.text),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _saving || _enteredPaise <= 0 ? null : _record,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.payments_outlined),
              label: Text(_saving
                  ? 'Saving…'
                  : 'Record ${Paise(_enteredPaise).display}'),
            ),
          ],
        ),
      ),
    );
  }

  /// The live amount for a session that has not been billed yet.
  int _liveEstimate() {
    final active = ref
        .watch(activeSessionsProvider)
        .value
        ?.where((a) => a.session.id == widget.session.id)
        .firstOrNull;
    if (active == null) return 0;
    final now = ref.watch(nowProvider).value ?? active.session.startedAt;
    return ref.read(sessionActionsProvider).liveBill(active, now).total.value;
  }

  Future<void> _record() async {
    setState(() => _saving = true);
    final amount = _enteredPaise;
    final note = _noteCtrl.text.trim();
    final result = await ref.read(sessionActionsProvider).recordPayment(
          RecordPaymentCommand(
            sessionId: widget.session.id,
            amountPaise: amount,
            method: _method,
            note: note.isEmpty ? null : note,
          ),
        );
    if (!mounted) return;
    if (result.isErr) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failureOrNull!.display)),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${Paise(amount).display} recorded by ${_methodLabel(_method)}.',
        ),
      ),
    );
  }

  String _methodLabel(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.billed,
    required this.collected,
    required this.remaining,
    required this.isEstimate,
  });

  final int billed;
  final int collected;
  final int remaining;
  final bool isEstimate;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    Widget row(String label, int paise, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: ArenaType.caption.copyWith(color: arena.textMuted)),
              Text(
                Paise(paise).display,
                style: AppTextStyles.mono(ArenaType.label)
                    .copyWith(color: color ?? arena.text),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        children: [
          row(isEstimate ? 'Estimated bill' : 'Final bill', billed),
          row('Collected', collected, color: arena.primary),
          const Divider(height: AppSpacing.lg),
          row(
            remaining > 0 ? 'Remaining' : 'Change due',
            remaining.abs(),
            color: remaining > 0 ? arena.warning : arena.textMuted,
          ),
        ],
      ),
    );
  }
}
