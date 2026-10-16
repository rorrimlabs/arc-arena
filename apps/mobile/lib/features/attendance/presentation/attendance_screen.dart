/// Clock in / clock out — the staff member's own attendance.
///
/// One button: it reads the phone's location (foreground, once), sends the
/// punch straight to the server (which stamps the time and judges the
/// location), and shows what was recorded. Nothing is queued offline: a punch
/// the server never saw is refused and can be sent again with the same id.
library;

import 'package:arena_ops/app/controllers/attendance_actions.dart';
import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/core/widgets/confirm_dialog.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_history_screen.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_labels.dart';
import 'package:arena_ops/features/leave/presentation/leave_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  static const String path = '/more/attendance';

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Busy { none, locating, sending }

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  _Busy _busy = _Busy.none;
  LocationReading? _reading;
  Failure? _failure;

  /// A punch the server may never have seen (connection dropped / busy):
  /// "Try again" resends it with the same id.
  PunchCommand? _unsent;

  Future<void> _refresh() async {
    ref.invalidate(myAttendanceProvider);
    ref.invalidate(myAttendanceDaysProvider);
    ref.invalidate(attendanceRulesProvider);
    await ref.read(myAttendanceProvider.future);
  }

  Future<void> _punch(PunchKind kind) async {
    if (_busy != _Busy.none) return;
    if (kind == PunchKind.clockOut) {
      final ok = await confirmAction(
        context,
        title: 'Clock out now?',
        message: 'Your day ends at the time the server records. '
            'Clock in again if you are still working.',
        confirm: 'Clock out',
      );
      if (!ok || !mounted) return;
    }
    final actions = ref.read(attendanceActionsProvider);
    setState(() {
      _busy = _Busy.locating;
      _failure = null;
      _unsent = null;
    });
    final reading = await actions.readLocation();
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _busy = _Busy.sending;
    });
    await _send(actions.prepare(kind, reading));
  }

  Future<void> _send(PunchCommand cmd) async {
    final res = await ref.read(attendanceActionsProvider).send(cmd);
    if (!mounted) return;
    switch (res) {
      case Ok(value: final outcome):
        setState(() {
          _busy = _Busy.none;
          _unsent = null;
        });
        ref.invalidate(myAttendanceProvider);
        ref.invalidate(myAttendanceDaysProvider);
        showToast(context, _recorded(outcome));
      case Err(failure: final f):
        setState(() {
          _busy = _Busy.none;
          _failure = f;
          _unsent = f.code == 'offline' || f.code == 'retry' ? cmd : null;
        });
    }
  }

  Future<void> _retry() async {
    final cmd = _unsent;
    if (cmd == null) return;
    setState(() {
      _busy = _Busy.sending;
      _failure = null;
    });
    await _send(cmd);
  }

  String _recorded(PunchOutcome o) {
    final what = o.kind == PunchKind.clockIn ? 'Clocked in' : 'Clocked out';
    final rules = ref.read(attendanceRulesProvider).value?.valueOrNull;
    final String? where = rules != null && !rules.checksLocation
        ? null
        : switch (o.verdict) {
            GeofenceVerdict.inside => 'inside the arena',
            GeofenceVerdict.outside => 'outside the arena',
            GeofenceVerdict.unknown => 'location unknown',
          };
    return [
      where == null
          ? '$what at ${IstTime.format12(o.serverAt)}.'
          : '$what at ${IstTime.format12(o.serverAt)} · $where.',
      if (o.needsReview) 'The owner will check this entry.',
      if (o.autoClosedEntryId != null)
        'Your earlier clock-in was left open and has been closed automatically.',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final entriesAsync = ref.watch(myAttendanceProvider);
    final rules = ref.watch(attendanceRulesProvider).value?.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'My leave',
            icon: const Icon(Icons.event_busy_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const LeaveScreen())),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const AttendanceHistoryScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: switch (entriesAsync) {
                  AsyncData(value: Ok(value: final entries)) =>
                    _content(context, entries, rules),
                  AsyncData(value: Err(failure: final f)) => [
                      _FailureCard(failure: f, onRetry: _refresh),
                    ],
                  AsyncError() => [
                      _FailureCard(
                        failure: const Failure(
                          message: "Your attendance couldn't be loaded.",
                          fix: 'Pull to refresh.',
                        ),
                        onRetry: _refresh,
                      ),
                    ],
                  _ => [
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                },
              ),
            ),
          ),
        ),
      ),
      backgroundColor: arena.bg,
    );
  }

  List<Widget> _content(
    BuildContext context,
    List<AttendanceEntry> entries,
    AttendanceRules? rules,
  ) {
    final arena = context.arena;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final open = openEntryOf(entries);
    final today = IstDate.fromUtc(now);
    final todays = entries.where((e) => e.workDate == today).toList();
    final kind = open == null ? PunchKind.clockIn : PunchKind.clockOut;
    final reading = _reading;
    final preview = reading == null || rules == null || !rules.checksLocation
        ? null
        : previewPunch(reading, rules);

    return [
      _StatusCard(open: open, now: now, lastOut: todays.where((e) => !e.isOpen).firstOrNull),
      const SizedBox(height: AppSpacing.lg),
      if (reading != null && preview != null) ...[
        _LocationLine(reading: reading, preview: preview),
        const SizedBox(height: AppSpacing.md),
      ],
      SizedBox(
        height: AppSpacing.minTarget,
        child: FilledButton.icon(
          onPressed: _busy == _Busy.none ? () => _punch(kind) : null,
          icon: _busy == _Busy.none
              ? Icon(kind == PunchKind.clockIn
                  ? Icons.login_rounded
                  : Icons.logout_rounded)
              : const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text(switch (_busy) {
            _Busy.locating => 'Getting your location…',
            _Busy.sending => 'Recording…',
            _Busy.none => kind == PunchKind.clockIn ? 'Clock in' : 'Clock out',
          }),
        ),
      ),
      if (_failure != null) ...[
        const SizedBox(height: AppSpacing.md),
        _FailureCard(
          failure: _failure!,
          onRetry: _unsent == null ? null : _retry,
          reading: reading,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      Text(
        _rulesNote(rules),
        style: ArenaType.caption.copyWith(color: arena.textMuted),
      ),
      const SizedBox(height: AppSpacing.xl),
      Row(
        children: [
          Expanded(
            child: Text('Today', style: ArenaType.h3.copyWith(color: arena.text)),
          ),
          Text(
            formatMinutesLabel(clockedOn(today, entries, now)),
            style: ArenaType.label.copyWith(color: arena.textMuted),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (todays.isEmpty)
        Text('No clock-ins today yet.',
            style: ArenaType.body.copyWith(color: arena.textMuted))
      else
        ArenaRowGroup(children: [
          for (final e in todays)
            AttendanceEntryRow(
              entry: e,
              now: now,
              showWhere: rules?.checksLocation ?? true,
            ),
        ]),
    ];
  }

  String _rulesNote(AttendanceRules? rules) {
    if (rules == null) return 'Your location is checked only when you tap.';
    if (!rules.checksLocation) {
      return 'Clock in when you start and clock out when you finish. '
          'The time is recorded by the server.';
    }
    if (rules.geofence == null) {
      return "The arena's location isn't set yet, so punches are recorded "
          "without a location check. Your location is checked only when you tap.";
    }
    return switch (rules.outsideRule) {
      OutsideRule.block =>
        'This arena accepts clock-ins only at the arena, with location on. '
            'Your location is checked only when you tap.',
      OutsideRule.flag =>
        "Punches away from the arena are recorded and marked for the owner to "
            'check. Your location is checked only when you tap.',
      OutsideRule.allow => 'Your location is checked only when you tap.',
    };
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.open, required this.now, this.lastOut});

  final AttendanceEntry? open;
  final DateTime now;
  final AttendanceEntry? lastOut;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final entry = open;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: entry == null ? arena.border : arena.success),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusDotLabel(
            label: entry == null ? 'Clocked out' : 'On the clock',
            color: entry == null ? arena.textMuted : arena.success,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (entry != null) ...[
            Text(formatClock(entry.workedAt(now)),
                style: ArenaType.timer.copyWith(color: arena.text)),
            Text('Since ${IstTime.format12(entry.inAt)}',
                style: ArenaType.body.copyWith(color: arena.textMuted)),
          ] else
            Text(
              lastOut?.outAt == null
                  ? 'Tap Clock in when you start work.'
                  : 'Last clocked out at ${IstTime.format12(lastOut!.outAt!)}.',
              style: ArenaType.body.copyWith(color: arena.textMuted),
            ),
        ],
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.reading, required this.preview});

  final LocationReading reading;
  final PunchPreview preview;

  @override
  Widget build(BuildContext context) {
    final c = verdictColors(context, preview.verdict);
    return Row(
      children: [
        Icon(
          reading.hasFix ? Icons.place_rounded : Icons.location_off_rounded,
          size: 18,
          color: c.fg,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            readingSummary(reading, preview),
            style: ArenaType.label.copyWith(color: c.fg),
          ),
        ),
      ],
    );
  }
}

class _FailureCard extends ConsumerWidget {
  const _FailureCard({required this.failure, this.onRetry, this.reading});

  final Failure failure;
  final VoidCallback? onRetry;
  final LocationReading? reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final status = reading?.status;
    final opener = ref.read(locationSettingsOpenerProvider);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.message,
              style: ArenaType.label.copyWith(color: arena.danger)),
          if (failure.fix != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(failure.fix!, style: ArenaType.body.copyWith(color: arena.text)),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              if (status == LocationStatus.deniedForever ||
                  status == LocationStatus.denied)
                TextButton(
                  onPressed: opener.openAppSettings,
                  child: const Text('Open app settings'),
                ),
              if (status == LocationStatus.gpsOff)
                TextButton(
                  onPressed: opener.openLocationSettings,
                  child: const Text('Turn on location'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One entry: in → out, how long, where, and anything flagged.
class AttendanceEntryRow extends StatelessWidget {
  const AttendanceEntryRow({
    super.key,
    required this.entry,
    required this.now,
    this.onTap,
    this.showWhere = true,
  });

  final AttendanceEntry entry;
  final DateTime now;
  final VoidCallback? onTap;

  /// Whether to say where each punch was (off while the arena does not check
  /// locations).
  final bool showWhere;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final inV = entry.inPunch?.verdict;
    final outV = entry.outPunch?.verdict;
    final range = entry.isOpen
        ? '${IstTime.format12(entry.inAt)} → now'
        : '${IstTime.format12(entry.inAt)} → ${IstTime.format12(entry.outAt!)}';
    return ArenaListRow(
      icon: entry.isOpen ? Icons.timelapse_rounded : Icons.check_circle_outline,
      iconColor: entry.isOpen ? arena.success : arena.textMuted,
      title: range,
      subtitle: [
        formatMinutesLabel(entry.workedAt(now)),
        if (showWhere && inV != null) 'In: ${verdictLabel(inV)}',
        if (showWhere && outV != null) 'Out: ${verdictLabel(outV)}',
        if (entry.closedAutomatically) 'Closed automatically',
      ].join(' · '),
      trailing: entry.needsReview
          ? ArenaTag(
              label: 'Owner will check',
              foreground: arena.warning,
              background: arena.warningSoft,
            )
          : null,
      chevron: onTap != null,
      onTap: onTap,
    );
  }
}
