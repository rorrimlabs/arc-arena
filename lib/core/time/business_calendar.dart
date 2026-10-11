/// Operating hours and happy-hour windows, resolved to concrete UTC intervals.
///
/// Values default to the center's current schedule (spec §4) but are held as
/// configuration so the owner can change them later without touching code
/// (no magic numbers in logic). Happy hour never applies on weekends or on a
/// public holiday (spec §4).
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:meta/meta.dart';

/// A window within a single IST day, as minutes from IST midnight.
@immutable
class DayWindow {
  const DayWindow(this.startMinute, this.endMinute)
      : assert(startMinute >= 0 && endMinute <= 24 * 60 && startMinute < endMinute);

  /// e.g. 14:00 → 17:00
  const DayWindow.hm(int startHour, int startMin, int endHour, int endMin)
      : startMinute = startHour * 60 + startMin,
        endMinute = endHour * 60 + endMin;

  final int startMinute;
  final int endMinute;

  Map<String, dynamic> toJson() => {'start': startMinute, 'end': endMinute};

  factory DayWindow.fromJson(Map<String, dynamic> j) =>
      DayWindow(j['start'] as int, j['end'] as int);
}

/// Weekday-indexed schedule. Keys are Dart weekdays: Mon=1 … Sun=7.
/// A missing/`null` entry means "closed" (open) or "no happy hour" (happy).
@immutable
class BusinessHours {
  const BusinessHours({required this.openByWeekday, required this.happyByWeekday});

  final Map<int, DayWindow?> openByWeekday;
  final Map<int, DayWindow?> happyByWeekday;

  /// The centre's configured schedule:
  /// **open Tue–Sun 14:00–23:00 (Monday closed)**; **happy Tue–Fri
  /// 14:00–17:00** (2:00 PM – 5:00 PM), never at the weekend.
  ///
  /// This is the seeded default only — the owner edits it in
  /// Settings → Opening hours and the value is persisted, so nothing in the
  /// pricing or availability path reads these constants at runtime.
  factory BusinessHours.current() {
    const open = DayWindow.hm(14, 0, 23, 0);
    const happy = DayWindow.hm(14, 0, 17, 0);
    return const BusinessHours(
      openByWeekday: {
        DateTime.monday: null, // closed
        DateTime.tuesday: open,
        DateTime.wednesday: open,
        DateTime.thursday: open,
        DateTime.friday: open,
        DateTime.saturday: open,
        DateTime.sunday: open,
      },
      happyByWeekday: {
        DateTime.monday: null,
        DateTime.tuesday: happy,
        DateTime.wednesday: happy,
        DateTime.thursday: happy,
        DateTime.friday: happy,
        DateTime.saturday: null,
        DateTime.sunday: null,
      },
    );
  }

  BusinessHours copyWith({
    Map<int, DayWindow?>? openByWeekday,
    Map<int, DayWindow?>? happyByWeekday,
  }) =>
      BusinessHours(
        openByWeekday: openByWeekday ?? this.openByWeekday,
        happyByWeekday: happyByWeekday ?? this.happyByWeekday,
      );

  Map<String, dynamic> toJson() => {
        'open': _mapToJson(openByWeekday),
        'happy': _mapToJson(happyByWeekday),
      };

  factory BusinessHours.fromJson(Map<String, dynamic> j) => BusinessHours(
        openByWeekday: _mapFromJson(j['open'] as Map<String, dynamic>),
        happyByWeekday: _mapFromJson(j['happy'] as Map<String, dynamic>),
      );

  static Map<String, dynamic> _mapToJson(Map<int, DayWindow?> m) =>
      m.map((k, v) => MapEntry(k.toString(), v?.toJson()));

  static Map<int, DayWindow?> _mapFromJson(Map<String, dynamic> j) =>
      j.map((k, v) => MapEntry(
            int.parse(k),
            v == null ? null : DayWindow.fromJson(v as Map<String, dynamic>),
          ));
}

class BusinessCalendar {
  BusinessCalendar({
    BusinessHours? hours,
    this.holidays = const {},
    this.closedDays = const {},
  }) : hours = hours ?? BusinessHours.current();

  final BusinessHours hours;

  /// Public holidays. Happy hour never applies on these days, but the centre
  /// still trades unless the day is also in [closedDays] (OWNER CONFIRMATION
  /// #26 — the rate rules only ever said happy hour is excluded).
  final Set<IstDate> holidays;

  /// Days the centre does not open at all, whatever the weekday schedule says.
  final Set<IstDate> closedDays;

  bool isHoliday(IstDate date) => holidays.contains(date);

  bool isOpenOn(IstDate date) =>
      !closedDays.contains(date) && hours.openByWeekday[date.weekday] != null;

  /// The operating window for an IST [date] as a UTC interval, or null if the
  /// centre is closed that day (weekday schedule or an explicit closure).
  UtcInterval? operatingWindow(IstDate date) {
    if (closedDays.contains(date)) return null;
    final w = hours.openByWeekday[date.weekday];
    if (w == null) return null;
    return _windowToUtc(date, w);
  }

  /// The happy-hour window for an IST [date], or null when happy hour does not
  /// apply (closed day, non-happy weekday, or a public holiday — spec §4).
  UtcInterval? happyWindow(IstDate date) {
    if (isHoliday(date) || closedDays.contains(date)) return null;
    final w = hours.happyByWeekday[date.weekday];
    if (w == null) return null;
    return _windowToUtc(date, w);
  }

  UtcInterval _windowToUtc(IstDate date, DayWindow w) {
    final start = IstTime(date.year, date.month, date.day, 0, 0)
        .toUtc()
        .add(Duration(minutes: w.startMinute));
    final end = IstTime(date.year, date.month, date.day, 0, 0)
        .toUtc()
        .add(Duration(minutes: w.endMinute));
    return UtcInterval(start, end);
  }
}
