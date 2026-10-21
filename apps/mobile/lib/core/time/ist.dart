/// Indian Standard Time helpers.
///
/// IST is a fixed UTC+05:30 offset with **no daylight saving**, so all IST math
/// uses a constant offset — no timezone database needed (documented assumption,
/// see docs/PLAN.md). The app stores instants in UTC and only converts to IST
/// wall-clock time to decide business rules: operating hours, pricing rules, and
/// the business day a session belongs to (spec §27–28).
library;

import 'package:meta/meta.dart';

/// The fixed IST offset from UTC.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// An IST wall-clock date/time, detached from any UTC instant. Used only for
/// reasoning about calendar day and minute-of-day. Do **not** feed this back
/// into UTC math without [IstTime.toUtc].
@immutable
class IstTime {
  const IstTime(this.year, this.month, this.day, this.hour, this.minute);

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;

  /// The IST wall clock for a UTC [instant].
  factory IstTime.fromUtc(DateTime instant) {
    final shifted = instant.toUtc().add(istOffset);
    return IstTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
    );
  }

  /// Minutes since IST midnight (0..1439).
  int get minuteOfDay => hour * 60 + minute;

  /// Dart weekday for this IST date: Mon=1 … Sun=7.
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// The IST calendar date this instant belongs to — the "business day".
  IstDate get date => IstDate(year, month, day);

  /// 12-hour clock like `7:00 PM`, as staff read times.
  String get clock12 {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h12:${minute.toString().padLeft(2, '0')} $ampm';
  }

  /// `7:00 PM` for a UTC instant.
  static String format12(DateTime instant) => IstTime.fromUtc(instant).clock12;

  /// Back to a UTC instant.
  DateTime toUtc() => DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

  @override
  bool operator ==(Object other) =>
      other is IstTime &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute);

  @override
  String toString() =>
      'IST $year-${_pad2(month)}-${_pad2(day)} ${_pad2(hour)}:${_pad2(minute)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

/// A bare IST calendar day (no time). The unit of a "business day".
@immutable
class IstDate implements Comparable<IstDate> {
  const IstDate(this.year, this.month, this.day);

  factory IstDate.fromUtc(DateTime instant) => IstTime.fromUtc(instant).date;

  /// Parse `YYYY-MM-DD`.
  factory IstDate.parse(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) throw FormatException('Bad IstDate: $iso');
    return IstDate(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  final int year;
  final int month;
  final int day;

  /// UTC instant of IST midnight that starts this day.
  DateTime startOfDayUtc() =>
      DateTime.utc(year, month, day).subtract(istOffset);

  /// UTC instant of IST midnight that starts the next day (exclusive end).
  DateTime endOfDayUtc() =>
      DateTime.utc(year, month, day).add(const Duration(days: 1)).subtract(istOffset);

  /// Dart weekday: Mon=1 … Sun=7.
  int get weekday => DateTime.utc(year, month, day).weekday;

  IstDate addDays(int days) {
    final d = DateTime.utc(year, month, day).add(Duration(days: days));
    return IstDate(d.year, d.month, d.day);
  }

  /// `2026-10-03`.
  String get iso =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(IstDate other) {
    final c = year.compareTo(other.year);
    if (c != 0) return c;
    final m = month.compareTo(other.month);
    if (m != 0) return m;
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is IstDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'IstDate($iso)';
}
