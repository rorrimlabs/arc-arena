import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const pricing = PricingService();

  // The demo afternoon rule is on: −20% PS5 / Pool, Tue–Fri 14:00–17:00.
  PricingQuote quote(String activity, int? controllers, DateTime s, DateTime e) {
    final r = pricing.quote(
      snapshot: currentSnapshot(rules: [afternoonRule()]),
      activityCode: activity,
      controllerCount: controllers,
      start: s,
      end: e,
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  group('reference dates have the expected weekdays', () {
    test('Friday / Saturday / Sunday / Monday', () {
      expect(fridayDate.weekday, DateTime.friday);
      expect(saturdayDate.weekday, DateTime.saturday);
      expect(sundayDate.weekday, DateTime.sunday);
      expect(mondayDate.weekday, DateTime.monday);
    });
  });

  group('PS5 standard rates (one clean hour, outside the rule window)', () {
    final s = ist(2026, 10, 2, 18, 0);
    final e = ist(2026, 10, 2, 19, 0);
    test('1 controller = ₹150', () => expect(quote('PS5', 1, s, e).amount, const Paise(15000)));
    test('2 controllers = ₹280', () => expect(quote('PS5', 2, s, e).amount, const Paise(28000)));
    test('3 controllers = ₹390', () => expect(quote('PS5', 3, s, e).amount, const Paise(39000)));
    test('4 controllers = ₹480', () => expect(quote('PS5', 4, s, e).amount, const Paise(48000)));
  });

  group('PS5 under the −20% rule (one clean hour inside the window, Friday)', () {
    final s = ist(2026, 10, 2, 14, 0);
    final e = ist(2026, 10, 2, 15, 0);
    test('1 controller = ₹120', () => expect(quote('PS5', 1, s, e).amount, const Paise(12000)));
    test('2 controllers = ₹224', () => expect(quote('PS5', 2, s, e).amount, const Paise(22400)));
    test('3 controllers = ₹312', () => expect(quote('PS5', 3, s, e).amount, const Paise(31200)));
    test('4 controllers = ₹384', () => expect(quote('PS5', 4, s, e).amount, const Paise(38400)));
    test('the quote names the rule and carries the adjusted unit price', () {
      final q = quote('PS5', 1, s, e);
      expect(q.rule?.name, 'Afternoon deal');
      expect(q.rule?.summary, 'Afternoon deal −20%');
      expect(q.segments.single.unitPrice, const Paise(12000));
      expect(q.segments.single.band, Band.standard);
    });
  });

  group('VR — ₹200 / 30 min unit, not in the rule', () {
    test('exactly 30 min = ₹200', () {
      final q = quote('VR', null, ist(2026, 10, 2, 18, 0), ist(2026, 10, 2, 18, 30));
      expect(q.amount, const Paise(20000));
      expect(q.segments.single.units, 1);
    });
    test('31 min rounds up to 2 units = ₹400 (OWNER #12 default)', () {
      final q = quote('VR', null, ist(2026, 10, 2, 18, 0), ist(2026, 10, 2, 18, 31));
      expect(q.amount, const Paise(40000));
      expect(q.segments.single.units, 2);
    });
    test('inside the rule window VR is still ₹200 (not listed)', () {
      final q = quote('VR', null, ist(2026, 10, 2, 14, 0), ist(2026, 10, 2, 14, 30));
      expect(q.amount, const Paise(20000));
      expect(q.rule, isNull);
    });
  });

  group('Pool', () {
    test('standard 1 hour = ₹275', () {
      expect(quote('POOL', null, ist(2026, 10, 2, 18, 0), ist(2026, 10, 2, 19, 0)).amount,
          const Paise(27500));
    });
    test('1 hour under the −20% rule = ₹220', () {
      expect(quote('POOL', null, ist(2026, 10, 2, 14, 0), ist(2026, 10, 2, 15, 0)).amount,
          const Paise(22000));
    });
  });

  group('Lounge — ₹2000 / hour, not in the rule', () {
    test('standard 1 hour = ₹2000', () {
      expect(quote('LOUNGE', null, ist(2026, 10, 2, 18, 0), ist(2026, 10, 2, 19, 0)).amount,
          const Paise(200000));
    });
    test('inside the rule window still ₹2000', () {
      final q = quote('LOUNGE', null, ist(2026, 10, 2, 14, 0), ist(2026, 10, 2, 15, 0));
      expect(q.amount, const Paise(200000));
      expect(q.rule, isNull);
    });
  });

  group('no rate configured', () {
    test('unknown controller count → Err(no_rate)', () {
      final r = pricing.quote(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 5,
        start: ist(2026, 10, 2, 18, 0),
        end: ist(2026, 10, 2, 19, 0),
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'no_rate');
    });
  });
}
