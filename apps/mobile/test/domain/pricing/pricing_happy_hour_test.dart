import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const pricing = PricingService();

  PricingQuote quote(
    String activity,
    int? controllers,
    DateTime s,
    DateTime e, {
    Set<IstDate> holidays = const {},
  }) {
    final r = pricing.quote(
      snapshot: currentSnapshot(holidays: holidays),
      activityCode: activity,
      controllerCount: controllers,
      start: s,
      end: e,
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  group('happy-hour boundary split (spec §16)', () {
    test('4:30→5:30 PS5 1c splits 30m happy + 30m standard = ₹60 + ₹75 = ₹135', () {
      final q = quote('PS5', 1, ist(2026, 10, 2, 16, 30), ist(2026, 10, 2, 17, 30));
      expect(q.segments.length, 2);
      expect(q.segments[0].band, Band.happy);
      expect(q.segments[0].amount, const Paise(6000)); // ₹120/hr × 30m
      expect(q.segments[1].band, Band.standard);
      expect(q.segments[1].amount, const Paise(7500)); // ₹150/hr × 30m
      expect(q.amount, const Paise(13500)); // ₹135
    });

    test('whole session stays happy when fully inside the window', () {
      final q = quote('PS5', 2, ist(2026, 10, 2, 14, 30), ist(2026, 10, 2, 15, 30));
      expect(q.segments.single.band, Band.happy);
      expect(q.amount, const Paise(22000));
    });

    test('exactly at 17:00 boundary → standard (half-open window)', () {
      // 17:00→18:00 is entirely standard.
      final q = quote('PS5', 1, ist(2026, 10, 2, 17, 0), ist(2026, 10, 2, 18, 0));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });

    test('starts before open-of-happy is fine: 13:30→14:30 → 30m std + 30m happy', () {
      final q = quote('PS5', 1, ist(2026, 10, 2, 13, 30), ist(2026, 10, 2, 14, 30));
      expect(q.segments.length, 2);
      expect(q.segments[0].band, Band.standard); // before 14:00
      expect(q.segments[1].band, Band.happy); // 14:00–14:30
      expect(q.amount, const Paise(13500)); // ₹75 + ₹60
    });

    test('Pool splits too: 4:30→5:30 = ₹110 happy + ₹137.5 std → ₹247.50 → ₹248', () {
      final q = quote('POOL', null, ist(2026, 10, 2, 16, 30), ist(2026, 10, 2, 17, 30));
      // happy ₹220/hr × 30m = ₹110 (11000); std ₹275/hr × 30m = ₹137.50 (13750)
      expect(q.subtotal, const Paise(24750));
      expect(q.amount, const Paise(24800)); // nearest ₹1 (₹247.50 → ₹248)
    });
  });

  // The centre trades Tue–Sun and runs happy hour Tue–Fri 2–5 PM. Monday is a
  // closed day, so nothing booked then is ever happy-rated.
  group('Tuesday–Friday happy hours (2:00 PM – 5:00 PM)', () {
    test('Tuesday 14:00→15:00 PS5 1c = ₹120 happy rate', () {
      final q = quote('PS5', 1, ist(2026, 10, 6, 14, 0), ist(2026, 10, 6, 15, 0));
      expect(q.segments.single.band, Band.happy);
      expect(q.amount, const Paise(12000));
    });

    test('Tuesday 14:00→15:00 Pool = ₹220 happy rate', () {
      final q = quote('POOL', null, ist(2026, 10, 6, 14, 0), ist(2026, 10, 6, 15, 0));
      expect(q.segments.single.band, Band.happy);
      expect(q.amount, const Paise(22000));
    });

    test('Tuesday 17:30→18:30 (outside happy hours) PS5 1c = ₹150 standard', () {
      final q = quote('PS5', 1, ist(2026, 10, 6, 17, 30), ist(2026, 10, 6, 18, 30));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });

    test('Tuesday 17:30→18:30 (outside happy hours) Pool = ₹275 standard', () {
      final q = quote('POOL', null, ist(2026, 10, 6, 17, 30), ist(2026, 10, 6, 18, 30));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(27500));
    });
  });

  group('Monday is a closed day — never happy-rated (brief §8)', () {
    test('the calendar reports Monday closed and Tuesday open', () {
      final cal = currentSnapshot().calendar;
      expect(cal.isOpenOn(const IstDate(2026, 10, 5)), isFalse, reason: 'Monday');
      expect(cal.operatingWindow(const IstDate(2026, 10, 5)), isNull);
      expect(cal.isOpenOn(const IstDate(2026, 10, 6)), isTrue, reason: 'Tuesday');
    });

    test('Monday 14:00→15:00 PS5 1c bills the standard ₹150, not ₹120', () {
      final q = quote('PS5', 1, ist(2026, 10, 5, 14, 0), ist(2026, 10, 5, 15, 0));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });

    test('Monday 14:00→15:00 Pool bills the standard ₹275, not ₹220', () {
      final q = quote('POOL', null, ist(2026, 10, 5, 14, 0), ist(2026, 10, 5, 15, 0));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(27500));
    });
  });

  group('happy hour never applies on weekends (spec §4)', () {
    test('Saturday 4:30→5:30 PS5 1c = full standard ₹150', () {
      final q = quote('PS5', 1, ist(2026, 10, 3, 16, 30), ist(2026, 10, 3, 17, 30));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });

    test('Sunday 14:00→15:00 PS5 1c = full standard ₹150', () {
      final q = quote('PS5', 1, ist(2026, 10, 4, 14, 0), ist(2026, 10, 4, 15, 0));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });

    test('Sunday 14:00→15:00 Pool = full standard ₹275', () {
      final q = quote('POOL', null, ist(2026, 10, 4, 14, 0), ist(2026, 10, 4, 15, 0));
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(27500));
    });
  });

  group('happy hour never applies on public holidays (spec §4)', () {
    test('Friday marked holiday → 2:00→3:00 PS5 1c = standard ₹150, not ₹120', () {
      final q = quote(
        'PS5',
        1,
        ist(2026, 10, 2, 14, 0),
        ist(2026, 10, 2, 15, 0),
        holidays: {fridayDate},
      );
      expect(q.segments.single.band, Band.standard);
      expect(q.amount, const Paise(15000));
    });
  });
}
