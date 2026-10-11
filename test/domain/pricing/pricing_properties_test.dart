import 'dart:math';

import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const pricing = PricingService();
  final snapshot = currentSnapshot();

  PricingQuote quote(String activity, int? controllers, DateTime s, DateTime e) {
    final r = pricing.quote(
      snapshot: snapshot,
      activityCode: activity,
      controllerCount: controllers,
      start: s,
      end: e,
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  // Random starts across a Friday, which has a happy window to exercise splits.
  final combos = <(String, int?)>[('PS5', 1), ('PS5', 4), ('POOL', null), ('VR', null)];

  test('amount and subtotal are never negative', () {
    final rng = Random(7);
    for (var i = 0; i < 400; i++) {
      final startMin = rng.nextInt(9 * 60); // within 14:00–23:00
      final start = ist(2026, 10, 2, 14, 0).add(Duration(minutes: startMin));
      final dur = rng.nextInt(240); // 0..239 min
      final end = start.add(Duration(minutes: dur));
      final (act, ctrl) = combos[rng.nextInt(combos.length)];
      final q = quote(act, ctrl, start, end);
      expect(q.amount.value, greaterThanOrEqualTo(0));
      expect(q.subtotal.value, greaterThanOrEqualTo(0));
    }
  });

  test('segments are contiguous and exactly cover the interval', () {
    final rng = Random(11);
    for (var i = 0; i < 400; i++) {
      final start = ist(2026, 10, 2, 14, 0).add(Duration(minutes: rng.nextInt(9 * 60)));
      final dur = 1 + rng.nextInt(239);
      final end = start.add(Duration(minutes: dur));
      final (act, ctrl) = combos[rng.nextInt(combos.length)];
      final q = quote(act, ctrl, start, end);

      expect(q.segments, isNotEmpty);
      expect(q.segments.first.interval.start, start);
      expect(q.segments.last.interval.end, end);
      for (var j = 1; j < q.segments.length; j++) {
        expect(q.segments[j].interval.start, q.segments[j - 1].interval.end,
            reason: 'gap between segments');
      }
    }
  });

  test('longer sessions never cost less (monotonic in duration)', () {
    final rng = Random(23);
    for (var i = 0; i < 400; i++) {
      final start = ist(2026, 10, 2, 14, 0).add(Duration(minutes: rng.nextInt(8 * 60)));
      final d1 = rng.nextInt(120);
      final extra = rng.nextInt(120);
      final (act, ctrl) = combos[rng.nextInt(combos.length)];
      final shorter = quote(act, ctrl, start, start.add(Duration(minutes: d1)));
      final longer = quote(act, ctrl, start, start.add(Duration(minutes: d1 + extra)));
      expect(longer.amount.value, greaterThanOrEqualTo(shorter.amount.value),
          reason: '$act/$ctrl start=$start d1=$d1 extra=$extra');
    }
  });
}
