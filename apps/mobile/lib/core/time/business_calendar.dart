/// Operating hours, resolved to concrete UTC intervals.
///
/// Values default to the center's current schedule (spec §4) but are held as
/// configuration so the owner can change them later without touching code
/// (no magic numbers in logic). Time-of-day prices are pricing rules
/// (`domain/pricing/pricing_rule.dart`), not part of the calendar.
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
/// A missing/`null` entry means "closed".
@immutable
class BusinessHours {
  const BusinessHours({required this.openByWeekday});

  final Map<int, DayWindow?> openByWeekday;

  /// The centre's configured schedule: **open Tue–Sun 14:00–23:00 (Monday
  /// closed)**. Must equal the server's `_pricing_snapshot` default for an
  /// arena that never saved hours, or a new session's snapshot is refused.
  ///
  /// This is the seeded default only — the owner edits it in
  /// Settings → Opening hours and the value is persisted, so nothing in the
  /// pricing or availability path reads these constants at runtime.
  factory BusinessHours.current() {
    const open = DayWindow.hm(14, 0, 23, 0);
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
    );
  }

  BusinessHours copyWith({Map<int, DayWindow?>? openByWeekday}) =>
      BusinessHours(openByWeekday: openByWeekday ?? this.openByWeekday);

  /// Same shape as the server's snapshot `hours`: `{open: {"1".."7": …}}`.
  Map<String, dynamic> toJson() => {'open': _mapToJson(openByWeekday)};

  /// Hours saved or frozen by older builds carry a second, retired window
  /// map next to `open`; it is ignored.
  factory BusinessHours.fromJson(Map<String, dynamic> j) => BusinessHours(
        openByWeekday: _mapFromJson(j['open'] as Map<String, dynamic>),
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

  /// Public holidays. The centre still trades unless the day is also in
  /// [closedDays] (OWNER CONFIRMATION #26); pricing rules can target or skip
  /// them (`holiday_mode`).
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
