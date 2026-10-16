/// One person's attendance on one IST day, as the server judges it
/// (attendance_days / _att_day) — the same figures the salary run uses, so the
/// app never recomputes them.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:meta/meta.dart';

enum DayStatus {
  present('present'),
  late('late'),
  halfDay('half_day'),
  absent('absent'),
  onLeave('on_leave'),
  halfLeave('half_leave'),
  holiday('holiday'),
  weekOff('week_off'),
  upcoming('upcoming'),
  notEmployed('not_employed');

  const DayStatus(this.wire);
  final String wire;

  static DayStatus fromWire(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => upcoming);
}

@immutable
class AttendanceDay {
  const AttendanceDay({
    required this.day,
    required this.status,
    this.schedMin = 0,
    this.workedMin = 0,
    this.extraMin = 0,
    this.late = false,
    this.early = false,
    this.leavePaid = 0,
    this.leaveLop = 0,
    this.holidayName,
    this.flags = const [],
    this.open = false,
    this.entries = 0,
  });

  final IstDate day;
  final DayStatus status;

  /// Scheduled minutes (shift length − break); 0 on a week off.
  final int schedMin;

  /// Clocked minutes after the break and rounding — what counts.
  final int workedMin;

  /// Minutes beyond the standard day (all of them on a holiday / week off).
  final int extraMin;
  final bool late;
  final bool early;
  final double leavePaid;
  final double leaveLop;
  final String? holidayName;
  final List<String> flags;

  /// Still on the clock (the figures run to now).
  final bool open;
  final int entries;

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        day: IstDate.parse(j['work_date'] as String),
        status: DayStatus.fromWire(j['status'] as String?),
        schedMin: (j['sched_min'] as num?)?.toInt() ?? 0,
        workedMin: (j['worked_min'] as num?)?.toInt() ?? 0,
        extraMin: (j['extra_min'] as num?)?.toInt() ?? 0,
        late: j['late'] == true,
        early: j['early'] == true,
        leavePaid: (j['leave_paid'] as num?)?.toDouble() ?? 0,
        leaveLop: (j['leave_lop'] as num?)?.toDouble() ?? 0,
        holidayName: j['holiday_name'] as String?,
        flags: [for (final f in (j['flags'] as List? ?? const [])) f as String],
        open: j['open'] == true,
        entries: (j['entries'] as num?)?.toInt() ?? 0,
      );
}
