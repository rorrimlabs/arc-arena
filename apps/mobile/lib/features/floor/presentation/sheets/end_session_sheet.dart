import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rupee_input.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/value/floor_options.dart';
import 'package:arena_ops/features/controllers/presentation/controller_choice_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// End a session and record payment (spec §14, §19–§20). The bill is computed
/// from every segment's configuration.
Future<void> showEndSessionSheet(BuildContext context, ActiveSession active) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.95,
      child: _EndSheet(active: active),
    ),
  );
}

class _EndSheet extends ConsumerStatefulWidget {
  const _EndSheet({required this.active});
  final ActiveSession active;
  @override
  ConsumerState<_EndSheet> createState() => _EndSheetState();
}

class _EndSheetState extends ConsumerState<_EndSheet> {
  late final DateTime _endAt;
  late final SegmentBill _bill;

  /// Past the booked end: the booked time's price and every minute's, shown
  /// beside the bill (which the overtime grace decides between).
  SegmentBill? _booked;
  SegmentBill? _whole;
  final _amountCtrl = TextEditingController();
  final _waiveReasonCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  /// The pick, or the first method the arena offers when the pick is not (floor options).
  PaymentMethod _offered(PaymentMethod picked) =>
      (ref.read(floorOptionsProvider).value ?? FloorOptions.defaults).methodOr(picked);
  bool _waived = false;
  bool _saving = false;

  Session get _session => widget.active.session;

  @override
  void initState() {
    super.initState();
    _endAt = ref.read(clockProvider).now();
    final actions = ref.read(sessionActionsProvider);
    _bill = actions.endSummary(_session, widget.active.segments, at: _endAt);
    if (_endAt.isAfter(_session.scheduledEndAt)) {
      _booked = actions.endSummary(_session, widget.active.segments,
          at: _endAt, bookedOnly: true);
      _whole = actions.endSummary(_session, widget.active.segments,
          at: _endAt, wholeTime: true);
    }
  }

  /// Money already taken against this session while it ran (Take payment).
  int _collected() =>
      (ref.read(paymentsForSessionProvider(_session.id)).value ?? const [])
          .fold<int>(0, (sum, p) => sum + p.amountPaise);

  bool _prefilled = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _waiveReasonCtrl.dispose();
    super.dispose();
  }

  /// A waive writes money off: it is never recorded without a reason.
  bool get _waiveReasonMissing =>
      _waived && _waiveReasonCtrl.text.trim().isEmpty;

  /// Exact paise for what is typed (never via a double); 0 when empty.
  int get _paidPaise => parseRupeesToPaise(_amountCtrl.text) ?? 0;

  /// Text that is not a rupee amount: End is held back rather than ending the
  /// session as if nothing had been paid.
  bool get _amountInvalid =>
      !_waived &&
      _amountCtrl.text.trim().isNotEmpty &&
      parseRupeesToPaise(_amountCtrl.text) == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Settle what is still due: an advance taken while the session ran is
    // already in the till and must not be collected (or counted) again.
    final payments =
        ref.watch(paymentsForSessionProvider(_session.id)).value;
    final collected =
        (payments ?? const []).fold<int>(0, (sum, p) => sum + p.amountPaise);
    final billed = _bill.total.value - collected;
    if (!_prefilled && payments != null) {
      _prefilled = true;
      _amountCtrl.text = billed > 0 ? paiseToRupeeInput(billed) : '';
    }
    final paid = _paidPaise;
    final change = paid - billed;
    final customer = ref.watch(customerByIdProvider(_session.customerId)).value;
    final resources = <String, String>{
      for (final r in ref.watch(resourcesProvider).value ?? const []) r.id: r.name,
    };
    final games = <String, String>{
      for (final g in ref.watch(allGamesProvider).value ?? const []) g.id: g.name,
    };

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ListView(
        children: [
          Text('End session', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(customer?.displayName ?? '', style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          _BillCard(bill: _bill, resources: resources, games: games),
          if (_booked != null && _whole != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _OvertimeCard(
              scheduledEnd: _session.scheduledEndAt,
              over: _endAt.difference(_session.scheduledEndAt),
              graceMinutes: ref
                  .read(sessionActionsProvider)
                  .overtimeGraceFor(_session, widget.active.segments),
              booked: _booked!,
              whole: _whole!,
              charged: _bill.total == _whole!.total &&
                  _whole!.total != _booked!.total,
            ),
          ],
          if (_bill.isIncomplete) ...[
            const SizedBox(height: AppSpacing.sm),
            _UnpricedWarning(bill: _bill, resources: resources),
          ],
          const SizedBox(height: AppSpacing.sm),
          BorrowedPadsNotice(
            sessionRef: Controller.sessionRef(_session.id),
            returning: _returning,
            onToggle: (id, on) => setState(
                () => on ? _returning.add(id) : _returning.remove(id)),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Payment', style: theme.textTheme.labelLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Waive (complimentary)'),
            value: _waived,
            onChanged: (v) => setState(() => _waived = v),
          ),
          if (_waived)
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
          if (!_waived) ...[
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in ref.watch(offeredPaymentMethodsProvider))
                  ChoiceChip(
                    label: Text(_methodLabel(m)),
                    selected: _offered(_method) == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Amount received (₹)',
                border: const OutlineInputBorder(),
                prefixText: '₹ ',
                errorText: _amountInvalid ? rupeeInputError : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (collected != 0)
              Text('Already collected ${Paise(collected).display} · '
                  'due now ${Paise(billed < 0 ? 0 : billed).display}',
                  style: theme.textTheme.bodySmall),
            _StatusLine(billed: billed, paid: paid, change: change),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed:
                _saving || _amountInvalid || _waiveReasonMissing ? null : _confirm,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'End & record'),
          ),
        ],
      ),
    );
  }

  /// Borrowed pads ticked as walked back; recorded once the session ends.
  final Set<String> _returning = {};

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    final toast = AppToast.of(context);
    final actions = ref.read(sessionActionsProvider);
    final end = await actions.end(_session, widget.active.segments,
        markWaived: _waived,
        waiveReason: _waived ? _waiveReasonCtrl.text : null,
        at: _endAt);
    if (end.isErr) {
      if (mounted) setState(() => _saving = false);
      toast.failure(end.failureOrNull!);
      return;
    }
    // The session no longer holds its pads: record the ticked returns.
    final notReturned = _returning.isEmpty
        ? 0
        : _returning.length - await returnPadsHome(ref, _returning);

    final billed = _bill.total.value - _collected();
    String message = 'Session ended';
    if (!_waived && _paidPaise > 0 && billed > 0) {
      final record = _paidPaise >= billed ? billed : _paidPaise;
      final paid = await actions.recordPayment(RecordPaymentCommand(
        sessionId: _session.id,
        amountPaise: record,
        method: _offered(_method),
      ));
      final change = _paidPaise - billed;
      if (paid.isErr) {
        // The session IS ended; only the money did not go in. Say so plainly
        // so nobody believes it was collected.
        message = 'Ended, but the payment was not recorded: '
            '${paid.failureOrNull!.display}';
      } else if (change > 0) {
        message = 'Paid. Return ${Paise(change).display} change.';
      } else if (_paidPaise < billed) {
        message = 'Partial. ${Paise(billed - _paidPaise).display} pending.';
      } else {
        message = 'Paid in full.';
      }
    } else if (_waived) {
      message = 'Session waived (complimentary).';
    } else if (billed <= 0) {
      message = billed < 0
          ? 'Paid in advance. ${Paise(-billed).display} more than the bill '
              'was collected; refund it if it is owed back.'
          : 'Paid in full.';
    } else {
      message = 'Ended. ${Paise(billed).display} pending.';
    }

    if (notReturned > 0) {
      message = '$message $notReturned pad${notReturned == 1 ? ' was' : 's were'} '
          'not marked returned; mark ${notReturned == 1 ? 'it' : 'them'} on the controller board.';
    }
    if (mounted) Navigator.of(context).pop();
    toast.show(message,
        kind: message.startsWith('Ended, but') ? ToastKind.error : ToastKind.success);
  }

  String _methodLabel(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}

/// Some time played could not be priced, so the total below is short. Staff
/// are told rather than handing over an under-stated bill (brief §12).
class _UnpricedWarning extends StatelessWidget {
  const _UnpricedWarning({required this.bill, required this.resources});
  final SegmentBill bill;
  final Map<String, String> resources;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: arena.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This total is incomplete',
                  style: ArenaType.label.copyWith(color: arena.warning),
                ),
                const SizedBox(height: 2),
                for (final u in bill.unpriced)
                  Text(
                    '${resources[u.segment.resourceId] ?? u.segment.resourceId}'
                    ' · ${u.segment.activityCode}'
                    '${u.segment.controllerCount == null ? '' : ' · ${u.segment.controllerCount} ctrl'}'
                    ' — ${u.reason}',
                    style: ArenaType.caption.copyWith(color: arena.text),
                  ),
                const SizedBox(height: 2),
                Text(
                  'Add the missing rate in Settings → Pricing, then bill again.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Played past the booked end: what the booked time costs, what the extra
/// minutes would add, and whether they are on this bill (owner's overtime
/// grace, Settings › Billing rules). The actual end is stored either way.
class _OvertimeCard extends StatelessWidget {
  const _OvertimeCard({
    required this.scheduledEnd,
    required this.over,
    required this.graceMinutes,
    required this.booked,
    required this.whole,
    required this.charged,
  });

  final DateTime scheduledEnd;
  final Duration over;
  final int graceMinutes;
  final SegmentBill booked;
  final SegmentBill whole;
  final bool charged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arena = context.arena;
    final extra = whole.total.value - booked.total.value;
    final overLabel = formatMinutesLabel(over);
    final note = graceMinutes <= 0
        ? 'Overtime is billed.'
        : charged
            ? 'Over the $graceMinutes-min grace: the whole time is billed.'
            : 'Within the $graceMinutes-min grace: not charged.';
    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: style ?? theme.textTheme.bodyMedium),
              Text(value,
                  style: AppTextStyles.mono(
                      (style ?? theme.textTheme.bodyMedium)!)),
            ],
          ),
        );
    return Container(
      key: const ValueKey('end-overtime'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: arena.warning),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Played $overLabel past the booked end '
              '(${IstTime.format12(scheduledEnd)})',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          row('Booked time', booked.total.display),
          row('Overtime $overLabel', '+${Paise(extra).display}'),
          row('With overtime', whole.total.display),
          const SizedBox(height: AppSpacing.xs),
          Text(note,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: charged ? arena.warning : arena.textMuted)),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill, required this.resources, required this.games});
  final SegmentBill bill;
  final Map<String, String> resources;
  final Map<String, String> games;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in bill.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text([
                          resources[line.segment.resourceId] ?? line.segment.resourceId,
                          line.segment.activityCode,
                          if (line.segment.controllerCount != null)
                            '${line.segment.controllerCount}🎮',
                          if (line.segment.gameId != null)
                            (games[line.segment.gameId] ?? 'Game'),
                        ].join(' · '), style: theme.textTheme.bodyMedium),
                        Text(
                          '${IstTime.format12(line.quote.segments.isEmpty ? line.segment.startedAt : line.quote.segments.first.interval.start)} · '
                          '${formatMinutesLabel(Duration(seconds: line.quote.playedSeconds))}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(line.quote.amount.display,
                      style: AppTextStyles.mono(theme.textTheme.bodyMedium!)),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: theme.textTheme.titleMedium),
              Text(bill.total.display, style: AppTextStyles.amount(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.billed, required this.paid, required this.change});
  final int billed;
  final int paid;
  final int change;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (paid <= 0) {
      text = 'Pending ${Paise(billed).display}';
    } else if (change > 0) {
      text = 'Change to return: ${Paise(change).display}';
    } else if (paid < billed) {
      text = 'Pending ${Paise(billed - paid).display}';
    } else {
      text = 'Paid in full';
    }
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}
