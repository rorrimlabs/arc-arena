/// My leave: the paid-leave balance of the current leave year (from the
/// joining date), every request with its status and — once decided — how many
/// days are paid and how many are loss of pay. Apply, and cancel. No pay
/// amounts appear here.
library;

import 'package:arena_ops/app/controllers/leave_actions.dart';
import 'package:arena_ops/app/providers/leave_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/core/widgets/confirm_dialog.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/features/leave/presentation/apply_leave_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  static const String path = '/more/leave';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final balance = ref.watch(myLeaveBalanceProvider);
    final requests = ref.watch(myLeaveRequestsProvider);

    Future<void> refresh() async {
      ref.invalidate(myLeaveBalanceProvider);
      ref.invalidate(myLeaveRequestsProvider);
      await ref.read(myLeaveRequestsProvider.future);
    }

    final failure = balance.value?.failureOrNull ?? requests.value?.failureOrNull;
    final bal = balance.value?.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('My leave')),
      backgroundColor: arena.bg,
      floatingActionButton: failure?.code == 'leave_needs_cloud'
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showApplyLeaveSheet(context, balance: bal),
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Apply for leave'),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                children: [
                  if (failure != null) ...[
                    Text(failure.message,
                        style: ArenaType.body.copyWith(color: arena.text)),
                    if (failure.fix != null)
                      Text(failure.fix!,
                          style: ArenaType.caption.copyWith(color: arena.textMuted)),
                  ] else if (bal == null || requests.value == null)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _BalanceCard(balance: bal),
                    const SizedBox(height: AppSpacing.xl),
                    Text('My requests', style: ArenaType.h3.copyWith(color: arena.text)),
                    const SizedBox(height: AppSpacing.sm),
                    if (requests.value!.valueOrNull!.isEmpty)
                      Text('No leave requests yet.',
                          style: ArenaType.body.copyWith(color: arena.textMuted))
                    else
                      ArenaRowGroup(children: [
                        for (final r in requests.value!.valueOrNull!)
                          _RequestRow(request: r),
                      ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _days(double d) =>
    '${d == d.roundToDouble() ? d.toInt() : d} ${d == 1 ? 'day' : 'days'}';

String _date(IstDate d) =>
    DateFormat('d MMM yyyy').format(DateTime.utc(d.year, d.month, d.day));

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAID LEAVE LEFT',
              style: ArenaType.overline.copyWith(color: arena.textSubtle)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_days(balance.balance)} of ${_days(balance.allowance + balance.adjustments)}',
            style: ArenaType.h1.copyWith(color: arena.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              'Used ${_days(balance.used)}',
              if (balance.pending > 0) '${_days(balance.pending)} waiting for approval',
            ].join(' · '),
            style: ArenaType.body.copyWith(color: arena.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Leave year ${_date(balance.yearStart)} – ${_date(balance.yearEnd)}, '
            'from your joining date (${_date(balance.joinedOn)}). Unused days do not carry over.',
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Leave beyond your balance can still be approved, as loss of pay (LOP).',
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
        ],
      ),
    );
  }
}

({String label, Color fg, Color bg}) _status(BuildContext context, LeaveStatus s) {
  final arena = context.arena;
  return switch (s) {
    LeaveStatus.pending => (label: 'Waiting', fg: arena.warning, bg: arena.warningSoft),
    LeaveStatus.approved => (label: 'Approved', fg: arena.success, bg: arena.successSoft),
    LeaveStatus.rejected => (label: 'Not approved', fg: arena.danger, bg: arena.dangerSoft),
    LeaveStatus.cancelled => (label: 'Cancelled', fg: arena.textMuted, bg: arena.surfaceSunken),
    LeaveStatus.cancelPending =>
      (label: 'Cancel requested', fg: arena.warning, bg: arena.warningSoft),
  };
}

String _range(LeaveRequest r) {
  final from = DateFormat('EEE d MMM').format(DateTime.utc(r.from.year, r.from.month, r.from.day));
  if (r.from == r.to) {
    return r.halfDay == HalfDay.none ? from : '$from · ${r.halfDay.label.toLowerCase()}';
  }
  return '$from – ${DateFormat('EEE d MMM').format(DateTime.utc(r.to.year, r.to.month, r.to.day))}';
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final s = _status(context, request.status);
    final r = request;
    return ArenaListRow(
      icon: Icons.event_busy_rounded,
      title: _range(r),
      subtitle: [
        _days(r.days),
        r.kind.label,
        if (r.paidDays != null && r.status == LeaveStatus.approved)
          r.lopDays == 0 ? 'all paid' : '${_days(r.paidDays!)} paid · ${_days(r.lopDays!)} LOP',
      ].join(' · '),
      trailing: ArenaTag(label: s.label, foreground: s.fg, background: s.bg),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _RequestSheet(request: r),
      ),
    );
  }
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.request});

  final LeaveRequest request;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  bool _busy = false;
  Failure? _failure;

  Future<void> _cancel() async {
    final pending = widget.request.status == LeaveStatus.pending;
    final ok = await confirmAction(
      context,
      title: pending ? 'Cancel this request?' : 'Ask to cancel this leave?',
      message: pending
          ? 'The request is withdrawn. Apply again if you still need the days off.'
          : 'A cancellation request is sent for approval. The leave stays until it is approved.',
      cancel: 'Keep it',
      confirm: pending ? 'Cancel request' : 'Ask to cancel',
      destructive: true,
    );
    if (!ok || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final res = await ref.read(leaveActionsProvider).cancel(widget.request.id);
    if (!mounted) return;
    switch (res) {
      case Ok(value: final status):
        ref.invalidate(myLeaveRequestsProvider);
        ref.invalidate(myLeaveBalanceProvider);
        Navigator.of(context).pop();
        showToast(context, status == LeaveStatus.cancelled
                ? 'Request cancelled.'
                : 'Cancellation sent. The leave stays until it is approved.');
      case Err(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final r = widget.request;
    final s = _status(context, r.status);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(_range(r), style: ArenaType.h2.copyWith(color: arena.text))),
              ArenaTag(label: s.label, foreground: s.fg, background: s.bg),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text('${_days(r.days)} · ${r.kind.label}',
                style: ArenaType.body.copyWith(color: arena.textMuted)),
            const SizedBox(height: AppSpacing.md),
            Text('Reason', style: ArenaType.label.copyWith(color: arena.textMuted)),
            Text(r.reason, style: ArenaType.body.copyWith(color: arena.text)),
            if (r.paidDays != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                r.lopDays == 0
                    ? 'All ${_days(r.days)} paid from your balance.'
                    : '${_days(r.paidDays!)} paid from your balance, ${_days(r.lopDays!)} '
                        'loss of pay (deducted from salary).',
                style: ArenaType.body.copyWith(color: arena.text),
              ),
            ],
            if (r.decisionNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Note from the approver',
                  style: ArenaType.label.copyWith(color: arena.textMuted)),
              Text(r.decisionNote!, style: ArenaType.body.copyWith(color: arena.text)),
            ],
            if (_failure != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_failure!.display, style: ArenaType.body.copyWith(color: arena.danger)),
            ],
            if (r.cancellable) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.minTarget,
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: Text(r.status == LeaveStatus.pending
                      ? 'Cancel request'
                      : 'Ask to cancel this leave'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
