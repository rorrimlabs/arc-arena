/// Apply for leave: planned or unplanned, the dates (a half day for a single
/// day), and why. The server counts the working days and keeps the rules
/// (planned starts today or later; unplanned may go back a few days).
library;

import 'package:arena_ops/app/controllers/leave_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/leave_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_segmented.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

Future<void> showApplyLeaveSheet(BuildContext context, {LeaveBalance? balance}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ApplyLeaveSheet(balance: balance),
    );

class ApplyLeaveSheet extends ConsumerStatefulWidget {
  const ApplyLeaveSheet({super.key, this.balance});

  final LeaveBalance? balance;

  @override
  ConsumerState<ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends ConsumerState<ApplyLeaveSheet> {
  LeaveKind _kind = LeaveKind.planned;
  late IstDate _from;
  late IstDate _to;
  HalfDay _half = HalfDay.none;
  final _reason = TextEditingController();
  bool _busy = false;
  Failure? _failure;

  /// Kept to resend with the same id after a dropped connection.
  LeaveRequestCommand? _unsent;

  @override
  void initState() {
    super.initState();
    _from = _to = IstDate.fromUtc(ref.read(clockProvider).now());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final today = IstDate.fromUtc(ref.read(clockProvider).now());
    final current = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: _kind == LeaveKind.unplanned ? 31 : 0)),
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    final d = IstDate(picked.year, picked.month, picked.day);
    setState(() {
      _unsent = null;
      if (start) {
        _from = d;
        if (_to.compareTo(d) < 0) _to = d;
      } else {
        _to = d;
        if (d.compareTo(_from) < 0) _from = d;
      }
      if (_from != _to) _half = HalfDay.none;
    });
  }

  Future<void> _send() async {
    final actions = ref.read(leaveActionsProvider);
    final cmd = _unsent ??
        actions.prepare(kind: _kind, from: _from, to: _to, halfDay: _half, reason: _reason.text);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final res = await actions.apply(cmd);
    if (!mounted) return;
    switch (res) {
      case Ok(value: final days):
        ref.invalidate(myLeaveRequestsProvider);
        ref.invalidate(myLeaveBalanceProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Leave requested: ${days == days.roundToDouble() ? days.toInt() : days} '
                'working ${days == 1 ? 'day' : 'days'}. You will see the decision here.')));
      case Err(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
          _unsent = f.code == 'offline' || f.code == 'retry' ? cmd : null;
        });
    }
  }

  String _fmt(IstDate d) => DateFormat('EEE d MMM').format(DateTime.utc(d.year, d.month, d.day));

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final single = _from == _to;
    final bal = widget.balance;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg,
            AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Apply for leave', style: ArenaType.h2.copyWith(color: arena.text)),
              const SizedBox(height: AppSpacing.md),
              ArenaSegmented<LeaveKind>(
                segments: [
                  for (final k in LeaveKind.values) ArenaSegment(k, k.label),
                ],
                value: _kind,
                onChanged: (k) => setState(() {
                  _kind = k;
                  _unsent = null;
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _kind == LeaveKind.planned
                    ? 'Planned: decided ahead. It starts today or later.'
                    : 'Unplanned: sick or an emergency. It can start a few days back.',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(start: true),
                    icon: const Icon(Icons.event_rounded),
                    label: Text('From ${_fmt(_from)}'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(start: false),
                    icon: const Icon(Icons.event_rounded),
                    label: Text('To ${_fmt(_to)}'),
                  ),
                ),
              ]),
              if (single) ...[
                const SizedBox(height: AppSpacing.md),
                ArenaSegmented<HalfDay>(
                  segments: [
                    for (final h in HalfDay.values) ArenaSegment(h, h.label),
                  ],
                  value: _half,
                  onChanged: (h) => setState(() {
                    _half = h;
                    _unsent = null;
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Reason'),
                onChanged: (_) => _unsent = null,
              ),
              if (bal != null)
                Text(
                  'You have ${bal.available <= 0 ? 'no' : _num(bal.available)} paid '
                  '${bal.available == 1 ? 'day' : 'days'} left (after requests waiting). '
                  'Days beyond that can still be approved as loss of pay. Only working '
                  'days count; week-offs and holidays are skipped.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
              if (_failure != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_failure!.message, style: ArenaType.label.copyWith(color: arena.danger)),
                if (_failure!.fix != null)
                  Text(_failure!.fix!, style: ArenaType.body.copyWith(color: arena.text)),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.minTarget,
                child: FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy
                      ? 'Sending…'
                      : _unsent != null
                          ? 'Try again'
                          : 'Send request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _num(double d) => d == d.roundToDouble() ? '${d.toInt()}' : '$d';
