/// Add missed time: ask for a stretch you never punched, or the right clock-out
/// for an entry that was never closed (or closed automatically). It waits for
/// the owner's approval and counts only then.
library;

import 'package:arena_ops/app/controllers/attendance_request_actions.dart';
import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_segmented.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

Future<void> showMissedTimeSheet(
  BuildContext context, {
  required List<AttendanceEntry> entries,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => MissedTimeSheet(entries: entries),
);

class MissedTimeSheet extends ConsumerStatefulWidget {
  const MissedTimeSheet({super.key, required this.entries});

  /// Your recent entries (newest first), for fixing a clock-out.
  final List<AttendanceEntry> entries;

  @override
  ConsumerState<MissedTimeSheet> createState() => _MissedTimeSheetState();
}

class _MissedTimeSheetState extends ConsumerState<MissedTimeSheet> {
  AttendanceRequestKind _kind = AttendanceRequestKind.add;
  late IstDate _date;
  TimeOfDay _in = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _out = const TimeOfDay(hour: 22, minute: 0);
  AttendanceEntry? _entry;
  final _reason = TextEditingController();
  bool _busy = false;
  Failure? _failure;

  /// Kept to resend with the same id after a dropped connection.
  AttendanceRequestCommand? _unsent;

  @override
  void initState() {
    super.initState();
    _date = IstDate.fromUtc(ref.read(clockProvider).now());
    // Open or closed-automatically entries are the likely ones to fix.
    for (final e in widget.entries) {
      if (e.isOpen || e.closedAutomatically) {
        _entry = e;
        _kind = AttendanceRequestKind.fixOut;
        break;
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime _at(IstDate d, TimeOfDay t) =>
      IstTime(d.year, d.month, d.day, t.hour, t.minute).toUtc();

  /// The stretch asked for; a clock-out at or before the clock-in is the next day.
  (DateTime?, DateTime) get _times {
    if (_kind == AttendanceRequestKind.fixOut) {
      final inAt = _entry?.inAt;
      final day = inAt == null ? _date : IstDate.fromUtc(inAt);
      var out = _at(day, _out);
      if (inAt != null && !out.isAfter(inAt)) {
        out = out.add(const Duration(days: 1));
      }
      return (inAt, out);
    }
    final inAt = _at(_date, _in);
    var out = _at(_date, _out);
    if (!out.isAfter(inAt)) out = out.add(const Duration(days: 1));
    return (inAt, out);
  }

  void _changed() => setState(() {
    _unsent = null;
    _failure = null;
  });

  Future<void> _pickDate() async {
    final today = IstDate.fromUtc(ref.read(clockProvider).now());
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(today.year, today.month - 2, today.day),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    _date = IstDate(picked.year, picked.month, picked.day);
    _changed();
  }

  Future<void> _pickTime({required bool clockIn}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: clockIn ? _in : _out,
    );
    if (picked == null || !mounted) return;
    clockIn ? _in = picked : _out = picked;
    _changed();
  }

  Future<void> _send() async {
    final actions = ref.read(attendanceRequestActionsProvider);
    final (inAt, outAt) = _times;
    final cmd =
        _unsent ??
        actions.prepare(
          kind: _kind,
          entryId: _entry?.id,
          inAt: inAt,
          outAt: outAt,
          reason: _reason.text,
        );
    setState(() {
      _busy = true;
      _failure = null;
    });
    final res = await actions.send(cmd);
    if (!mounted) return;
    switch (res) {
      case Ok():
        ref.invalidate(myAttendanceRequestsProvider);
        Navigator.of(context).pop();
        showToast(
          context,
          'Request sent. It counts once the owner approves it.',
        );
      case Err(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
          _unsent = f.code == 'offline' || f.code == 'retry' ? cmd : null;
        });
    }
  }

  String _entryLabel(AttendanceEntry e) {
    final day = DateFormat('EEE d MMM').format(e.inAt.add(istOffset));
    final out = e.outAt == null
        ? 'still clocked in'
        : '${IstTime.format12(e.outAt!)}${e.closedAutomatically ? ' (closed automatically)' : ''}';
    return '$day · ${IstTime.format12(e.inAt)} → $out';
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final (inAt, outAt) = _times;
    final fixable = [for (final e in widget.entries.take(14)) e];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add missed time',
                style: ArenaType.h2.copyWith(color: arena.text),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Forgot to clock in or out? Ask here. It counts once the owner approves it.',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              ArenaSegmented<AttendanceRequestKind>(
                segments: [
                  for (final k in AttendanceRequestKind.values)
                    ArenaSegment(k, k.label),
                ],
                value: _kind,
                onChanged: (k) {
                  _kind = k;
                  _changed();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_kind == AttendanceRequestKind.add) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    DateFormat(
                      'EEE d MMM yyyy',
                    ).format(DateTime.utc(_date.year, _date.month, _date.day)),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _pickTime(clockIn: true),
                        child: Text('In ${IstTime.format12(inAt!)}'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _pickTime(clockIn: false),
                        child: Text(
                          'Out ${IstTime.format12(outAt)}'
                          '${IstDate.fromUtc(outAt) != IstDate.fromUtc(inAt) ? ' (next day)' : ''}',
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                if (fixable.isEmpty)
                  Text(
                    'No recent entries to fix.',
                    style: ArenaType.body.copyWith(color: arena.textMuted),
                  )
                else
                  for (final e in fixable)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        _entry?.id == e.id
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: _entry?.id == e.id
                            ? arena.primary
                            : arena.textMuted,
                      ),
                      title: Text(
                        _entryLabel(e),
                        style: ArenaType.body.copyWith(color: arena.text),
                      ),
                      onTap: _busy
                          ? null
                          : () {
                              _entry = e;
                              _changed();
                            },
                    ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _busy || _entry == null
                      ? null
                      : () => _pickTime(clockIn: false),
                  child: Text(
                    _entry == null
                        ? 'Pick the entry first'
                        : 'Clocked out at ${IstTime.format12(outAt)}'
                              '${inAt != null && IstDate.fromUtc(outAt) != IstDate.fromUtc(inAt) ? ' (next day)' : ''}',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. phone battery was dead',
                ),
                onChanged: (_) => _unsent = null,
              ),
              if (_failure != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _failure!.message,
                  style: ArenaType.label.copyWith(color: arena.danger),
                ),
                if (_failure!.fix != null)
                  Text(
                    _failure!.fix!,
                    style: ArenaType.body.copyWith(color: arena.text),
                  ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.minTarget,
                child: FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(
                    _busy
                        ? 'Sending…'
                        : _unsent != null
                        ? 'Try again'
                        : 'Send request',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
