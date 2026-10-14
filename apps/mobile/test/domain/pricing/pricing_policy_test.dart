import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const pricing = PricingService();

  PricingQuote q(
    BillingPolicy policy,
    String activity,
    int? controllers,
    DateTime s,
    DateTime e,
  ) {
    final r = pricing.quote(
      snapshot: currentSnapshot(policy: policy),
      activityCode: activity,
      controllerCount: controllers,
      start: s,
      end: e,
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  // Friday evening (no rules in this file's snapshot).
  final s18 = ist(2026, 10, 2, 18, 0);

  group('grace period (OWNER #3)', () {
    final policy = BillingPolicy.defaults.copyWith(graceMinutes: 5);
    test('under grace is free', () {
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 4)));
      expect(r.amount, Paise.zero);
      expect(r.isFree, isTrue);
    });
    test('over grace bills full actual time', () {
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 6)));
      expect(r.amount, const Paise(1500)); // 6 min of ₹150/hr = ₹15
    });
  });

  group('minimum session charge (OWNER #4)', () {
    final policy = BillingPolicy.defaults.copyWith(minimumChargeMinutes: 30);
    test('a 10-minute session is billed as 30 minutes', () {
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 10)));
      expect(r.playedMinutes, 10);
      expect(r.billedMinutes, 30);
      expect(r.amount, const Paise(7500)); // 30 min of ₹150/hr = ₹75
    });
    test('a session above the minimum is unaffected', () {
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 40)));
      expect(r.billedMinutes, 40);
    });
  });

  group('block billing (OWNER #1/#2)', () {
    test('block_60 round up: 61 min → 2 hours = ₹300', () {
      final policy = BillingPolicy.defaults
          .copyWith(billingUnit: BillingUnit.block60, blockRounding: Rounding.up);
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 61)));
      expect(r.billedMinutes, 120);
      expect(r.amount, const Paise(30000));
    });
    test('block_60 nearest: 61 min → 1 hour = ₹150', () {
      final policy = BillingPolicy.defaults
          .copyWith(billingUnit: BillingUnit.block60, blockRounding: Rounding.nearest);
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 61)));
      expect(r.billedMinutes, 60);
      expect(r.amount, const Paise(15000));
    });
    test('block_15 round up: 31 min → 45 min = ₹112.50 → ₹113 (nearest ₹1)', () {
      final policy = BillingPolicy.defaults
          .copyWith(billingUnit: BillingUnit.block15, blockRounding: Rounding.up);
      final r = q(policy, 'PS5', 1, s18, s18.add(const Duration(minutes: 31)));
      expect(r.billedMinutes, 45);
      expect(r.subtotal, const Paise(11250));
      expect(r.amount, const Paise(11300));
    });
  });

  group('VR partial-unit rounding (OWNER #12)', () {
    test('nearest: 45 min → 2 units = ₹400 (ties up)', () {
      final policy = BillingPolicy.defaults.copyWith(vrUnitRounding: VrUnitRounding.nearest);
      final r = q(policy, 'VR', null, s18, s18.add(const Duration(minutes: 45)));
      expect(r.amount, const Paise(40000));
    });
    test('nearest: 44 min → 1 unit = ₹200', () {
      final policy = BillingPolicy.defaults.copyWith(vrUnitRounding: VrUnitRounding.nearest);
      final r = q(policy, 'VR', null, s18, s18.add(const Duration(minutes: 44)));
      expect(r.amount, const Paise(20000));
    });
    test('prorate: 45 min = ₹300 (1.5 units × ₹200)', () {
      final policy = BillingPolicy.defaults.copyWith(vrUnitRounding: VrUnitRounding.prorate);
      final r = q(policy, 'VR', null, s18, s18.add(const Duration(minutes: 45)));
      expect(r.amount, const Paise(30000));
    });
  });

  group('money rounding (OWNER #16)', () {
    // PS5 1c for 49 min per-minute = ₹122.50 (12250 paise) subtotal.
    final e49 = ist(2026, 10, 2, 18, 49);
    test('nearest ₹10: ₹122.50 → ₹120', () {
      final policy = BillingPolicy.defaults
          .copyWith(moneyRoundingPaise: 1000, moneyRoundingDir: MoneyRoundingDir.nearest);
      expect(q(policy, 'PS5', 1, s18, e49).amount, const Paise(12000));
    });
    test('round up ₹10: ₹122.50 → ₹130', () {
      final policy = BillingPolicy.defaults
          .copyWith(moneyRoundingPaise: 1000, moneyRoundingDir: MoneyRoundingDir.up);
      expect(q(policy, 'PS5', 1, s18, e49).amount, const Paise(13000));
    });
    test('nearest ₹5: ₹127.50 (51 min) → ₹130', () {
      final policy = BillingPolicy.defaults
          .copyWith(moneyRoundingPaise: 500, moneyRoundingDir: MoneyRoundingDir.nearest);
      expect(q(policy, 'PS5', 1, s18, ist(2026, 10, 2, 18, 51)).amount, const Paise(13000));
    });
  });

  group('rounding scope (OWNER #7)', () {
    // A quote is one priced piece now (time-of-day prices are rules, not
    // band splits), so both scopes round the same exact amount once:
    // Pool per-minute, 30 min 7 s = 27500 × 1807 / 3600 = 13803.47 → ₹138.03.
    final s = ist(2026, 10, 2, 16, 43);
    final e = ist(2026, 10, 2, 17, 13).add(const Duration(seconds: 7));
    for (final scope in RoundingScope.values) {
      test('${scope.name} scope: ₹138.03 in one line', () {
        final policy = BillingPolicy.defaults
            .copyWith(roundingScope: scope, moneyRoundingPaise: 1);
        final r = q(policy, 'POOL', null, s, e);
        expect(r.subtotal, const Paise(13803));
        expect(r.segments, hasLength(1));
      });
    }
  });

  group('interval edge cases', () {
    test('end == start → free zero quote', () {
      final r = q(BillingPolicy.defaults, 'PS5', 1, s18, s18);
      expect(r.amount, Paise.zero);
      expect(r.segments, isEmpty);
    });
    test('end before start → Err(invalid_interval)', () {
      final r = pricing.quote(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 1,
        start: s18,
        end: s18.subtract(const Duration(minutes: 1)),
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'invalid_interval');
    });
  });
}
