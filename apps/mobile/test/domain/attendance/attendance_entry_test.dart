import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart' show ist;

void main() {
  const today = IstDate(2026, 10, 15);
  final now = ist(2026, 10, 15, 18, 0);

  AttendanceEntry entry(String id, DateTime inAt, [DateTime? outAt, IstDate? day]) =>
      AttendanceEntry(id: id, workDate: day ?? today, inAt: inAt, outAt: outAt);

  test('workedAt: to the clock-out, or to now while open', () {
    expect(entry('a', ist(2026, 10, 15, 11, 0), ist(2026, 10, 15, 14, 30)).workedAt(now),
        const Duration(hours: 3, minutes: 30));
    expect(entry('b', ist(2026, 10, 15, 16, 0)).workedAt(now), const Duration(hours: 2));
  });

  test('openEntryOf picks the open stretch', () {
    final closed = entry('a', ist(2026, 10, 15, 11, 0), ist(2026, 10, 15, 14, 0));
    final open = entry('b', ist(2026, 10, 15, 16, 0));
    expect(openEntryOf([closed, open]), open);
    expect(openEntryOf([closed]), isNull);
  });

  test('clockedOn adds the day\'s stretches (split shift), open one to now', () {
    final entries = [
      entry('a', ist(2026, 10, 15, 11, 0), ist(2026, 10, 15, 14, 0)),
      entry('b', ist(2026, 10, 15, 16, 0)),
      // Yesterday's night shift that ran past midnight belongs to yesterday.
      entry('c', ist(2026, 10, 14, 20, 0), ist(2026, 10, 15, 2, 0), today.addDays(-1)),
    ];
    expect(clockedOn(today, entries, now), const Duration(hours: 5));
    expect(clockedOn(today.addDays(-1), entries, now), const Duration(hours: 6));
  });
}
