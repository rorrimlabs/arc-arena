/// The staff member's own attendance log: every entry of the last month by
/// day, each with where the punches were made (map pin and inside / outside).
library;

import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_labels.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_screen.dart';
import 'package:arena_ops/features/attendance/presentation/widgets/punch_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  static const String path = '/more/attendance/history';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final async = ref.watch(myAttendanceProvider);
    // The server's verdict per day; the log still shows if it cannot be read.
    final days = ref.watch(myAttendanceDaysProvider).value?.valueOrNull ?? const [];
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final rules = ref.watch(attendanceRulesProvider).value?.valueOrNull;

    Future<void> refresh() async {
      ref.invalidate(myAttendanceProvider);
      ref.invalidate(myAttendanceDaysProvider);
      await ref.read(myAttendanceProvider.future);
    }

    Widget message(String text, {String? fix}) => ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(text, style: ArenaType.body.copyWith(color: arena.text)),
            if (fix != null)
              Text(fix, style: ArenaType.caption.copyWith(color: arena.textMuted)),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
      backgroundColor: arena.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: switch (async) {
                AsyncData(value: Ok(value: final entries))
                    when entries.isEmpty && !days.any(_worthShowing) =>
                  message('No clock-ins in the last $attendanceHistoryDays days.'),
                AsyncData(value: Ok(value: final entries)) =>
                  _DayList(
                    entries: entries,
                    days: days,
                    now: now,
                    showWhere: rules?.checksLocation ?? true,
                  ),
                AsyncData(value: Err(failure: final f)) =>
                  message(f.message, fix: f.fix),
                AsyncError() => message("Your attendance couldn't be loaded.",
                    fix: 'Pull to refresh.'),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A day without clock-ins still matters when the server says something
/// about it (absent, on leave, a holiday).
bool _worthShowing(AttendanceDay d) =>
    d.entries > 0 ||
    d.status == DayStatus.absent ||
    d.status == DayStatus.onLeave ||
    d.status == DayStatus.halfLeave ||
    d.status == DayStatus.holiday;

class _DayList extends StatelessWidget {
  const _DayList({
    required this.entries,
    required this.days,
    required this.now,
    required this.showWhere,
  });

  final List<AttendanceEntry> entries;
  final List<AttendanceDay> days;
  final DateTime now;
  final bool showWhere;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final byDay = {for (final d in days) d.day: d};
    final dates = <IstDate>{
      for (final e in entries) e.workDate,
      for (final d in days)
        if (_worthShowing(d)) d.day,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        for (final date in dates) ...[
          _DayHeader(
            date: date,
            day: byDay[date],
            // The server's counted minutes (break, rounding) when it has the
            // day, else the raw clocked time.
            counted: byDay[date]?.workedMin != null && byDay[date]!.entries > 0
                ? Duration(minutes: byDay[date]!.workedMin)
                : clockedOn(date, entries, now),
          ),
          if (entries.any((e) => e.workDate == date))
            ArenaRowGroup(children: [
              for (final e in entries.where((e) => e.workDate == date))
                AttendanceEntryRow(
                  entry: e,
                  now: now,
                  showWhere: showWhere,
                  onTap: () => showEntryDetail(context, e, now),
                ),
            ])
          else
            Text(
              switch (byDay[date]?.status) {
                DayStatus.holiday => byDay[date]!.holidayName ?? 'Holiday',
                DayStatus.onLeave || DayStatus.halfLeave => 'Approved leave',
                _ => 'No clock-in',
              },
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.day, required this.counted});

  final IstDate date;
  final AttendanceDay? day;
  final Duration counted;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final d = day;
    final c = d == null ? null : dayStatusColors(context, d.status);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            DateFormat('EEE d MMM')
                .format(DateTime.utc(date.year, date.month, date.day)),
            style: ArenaType.h3.copyWith(color: arena.text),
          ),
          if (d != null && c != null && d.status != DayStatus.notEmployed)
            ArenaTag(label: dayStatusLabel(d.status), foreground: c.fg, background: c.bg),
          Text(
            [
              formatMinutesLabel(counted),
              if (d != null && d.extraMin > 0)
                '+${formatMinutesLabel(Duration(minutes: d.extraMin))} extra',
            ].join(' · '),
            style: ArenaType.label.copyWith(color: arena.textMuted),
          ),
        ],
      ),
    );
  }
}

Future<void> showEntryDetail(
    BuildContext context, AttendanceEntry entry, DateTime now) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EntryDetailSheet(entry: entry, now: now),
  );
}

class EntryDetailSheet extends StatelessWidget {
  const EntryDetailSheet({super.key, required this.entry, required this.now});

  final AttendanceEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          children: [
            Text(
              entry.isOpen
                  ? 'On the clock · ${formatMinutesLabel(entry.workedAt(now))}'
                  : formatMinutesLabel(entry.workedAt(now)),
              style: ArenaType.h2.copyWith(color: arena.text),
            ),
            if (entry.needsReview || entry.flags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (entry.needsReview)
                    ArenaTag(
                      label: 'Owner will check',
                      foreground: arena.warning,
                      background: arena.warningSoft,
                    ),
                  for (final f in entry.flags)
                    ArenaTag(
                      label: flagLabel(f),
                      foreground: arena.textMuted,
                      background: arena.surfaceSunken,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PunchMap(entry: entry),
            const SizedBox(height: AppSpacing.lg),
            _PunchDetail(title: 'Clock-in', punch: entry.inPunch, at: entry.inAt),
            const SizedBox(height: AppSpacing.md),
            if (entry.isOpen)
              Text('Not clocked out yet.',
                  style: ArenaType.body.copyWith(color: arena.textMuted))
            else
              _PunchDetail(
                title: entry.closedAutomatically
                    ? 'Closed automatically'
                    : 'Clock-out',
                punch: entry.outPunch,
                at: entry.outAt!,
                note: entry.closedAutomatically
                    ? 'The clock-in was left open too long, so it was closed '
                        'at this time. The owner will check it.'
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _PunchDetail extends StatelessWidget {
  const _PunchDetail({
    required this.title,
    required this.punch,
    required this.at,
    this.note,
  });

  final String title;
  final AttendancePunch? punch;
  final DateTime at;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final p = punch;
    final c = p == null ? null : verdictColors(context, p.verdict);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$title · ${IstTime.format12(at)}',
                    style: ArenaType.label.copyWith(color: arena.text)),
              ),
              if (p != null && c != null)
                ArenaTag(
                    label: verdictLabel(p.verdict),
                    foreground: c.fg,
                    background: c.bg),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note!, style: ArenaType.caption.copyWith(color: arena.textMuted)),
          ],
          if (p != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                wireLocationStatusLabel(p.locationStatus),
                if (p.distanceM != null) '${p.distanceM} m from the arena',
                if (p.accuracyM != null) '±${p.accuracyM!.round()} m',
                if (p.isMocked == true) 'fake location',
              ].join(' · '),
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
