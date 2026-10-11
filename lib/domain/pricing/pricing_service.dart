/// The pricing engine (spec §15–§18). PURE Dart — no Flutter, no Supabase, no
/// UI. Deterministic given a [PricingSnapshot] and a time interval, so a session
/// priced today prices identically forever.
///
/// Flow (spec §15):
///   1. Validate the interval.
///   2. Apply grace (free if under grace) and minimum-charge (extend interval).
///   3. Split the interval at every happy-hour boundary (spec §16).
///   4. For each segment, resolve the band rate (happy → standard fallback).
///   5. Apply the billing policy to get billed time/units.
///   6. Compute amounts in integer paise (never floating point).
///   7. Round per rounding-scope, then apply final cash rounding.
///
/// Late arrival (§8) and early exit (§5) are decided by the *caller* choosing
/// which interval to price; the engine stays pure over `[start, end]`.
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rounding.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';

class PricingService {
  const PricingService();

  Result<PricingQuote> quote({
    required PricingSnapshot snapshot,
    required String activityCode,
    required int? controllerCount,
    required DateTime start,
    required DateTime end,
  }) {
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();

    if (endUtc.isBefore(startUtc)) {
      return const Err(Failure(
        message: 'Invalid session time.',
        fix: 'End time is before start time.',
        code: 'invalid_interval',
      ));
    }

    final activity = snapshot.activity(activityCode);
    if (activity == null) {
      return Err(Failure(
        message: 'No price is configured for this combination.',
        fix: 'Set up a rate for $activityCode.',
        code: 'no_rate',
      ));
    }

    final policy = snapshot.policy;
    final totalSeconds = endUtc.difference(startUtc).inSeconds;

    // Grace: nothing to pay if under the grace period (default 0 → never free).
    if (totalSeconds <= policy.graceMinutes * 60) {
      return Ok(PricingQuote(
        segments: const [],
        playedSeconds: totalSeconds,
        billedMinutes: 0,
        subtotal: Paise.zero,
        amount: Paise.zero,
      ));
    }

    // Minimum charge: bill at least this much time by extending the interval.
    final minSeconds = policy.minimumChargeMinutes * 60;
    final billedEnd = totalSeconds < minSeconds
        ? startUtc.add(Duration(seconds: minSeconds))
        : endUtc;

    final actual = UtcInterval(startUtc, endUtc);
    final bandSegs = _bandSegments(startUtc, billedEnd, activity, snapshot.calendar);

    final segments = <PricingSegment>[];
    var subtotalNumerator = 0;
    int? commonDen;
    var mixedDen = false;
    var totalBilledMinutes = 0;

    for (final bs in bandSegs) {
      final rate = _resolveRate(
        snapshot: snapshot,
        activityCode: activityCode,
        band: bs.band,
        controllerCount: controllerCount,
        happyEligible: activity.happyEligible,
      );
      if (rate == null) {
        return Err(Failure(
          message: 'No price is configured for this combination.',
          fix: controllerCount == null
              ? 'Add a $activityCode rate in Settings → Pricing.'
              : 'Add a $activityCode rate for $controllerCount '
                  'controller${controllerCount == 1 ? '' : 's'} '
                  'in Settings → Pricing.',
          code: 'no_rate',
        ));
      }

      final billedSeconds = bs.interval.duration.inSeconds;
      final playedSeconds =
          actual.intersection(bs.interval)?.duration.inSeconds ?? 0;

      final _SegMath m = activity.durationModel == DurationModel.unit
          ? _unitCharge(billedSeconds, rate, policy)
          : _timeCharge(billedSeconds, rate, policy);

      commonDen ??= m.den;
      if (m.den != commonDen) mixedDen = true;
      subtotalNumerator += m.num;
      totalBilledMinutes += m.billedMinutes;

      segments.add(PricingSegment(
        interval: bs.interval,
        band: bs.band,
        playedSeconds: playedSeconds,
        billedMinutes: m.billedMinutes,
        units: m.units,
        unitMinutes: rate.unitMinutes,
        unitPrice: rate.price,
        amount: Paise(roundDivHalfUp(m.num, m.den)),
        rawNumerator: m.num,
        rawDenominator: m.den,
      ));
    }

    // Rounding scope: round each segment (segment) or once at the end (session).
    final int subtotalPaise;
    if (policy.roundingScope == RoundingScope.segment || mixedDen) {
      subtotalPaise =
          segments.fold<int>(0, (sum, s) => sum + s.amount.value);
    } else {
      subtotalPaise = roundDivHalfUp(subtotalNumerator, commonDen ?? 1);
    }

    final finalPaise = applyMoneyRounding(
      subtotalPaise,
      policy.moneyRoundingPaise,
      policy.moneyRoundingDir,
    );

    return Ok(PricingQuote(
      segments: segments,
      playedSeconds: totalSeconds,
      billedMinutes: totalBilledMinutes,
      subtotal: Paise(subtotalPaise),
      amount: Paise(finalPaise),
    ));
  }

  // --- band resolution -------------------------------------------------------

  Rate? _resolveRate({
    required PricingSnapshot snapshot,
    required String activityCode,
    required Band band,
    required int? controllerCount,
    required bool happyEligible,
  }) {
    var rate = snapshot.rateFor(
      activityCode: activityCode,
      band: band,
      controllerCount: controllerCount,
    );
    // Fall back to the standard rate when no special rate exists (spec §15 #6).
    if (rate == null && band == Band.happy) {
      rate = snapshot.rateFor(
        activityCode: activityCode,
        band: Band.standard,
        controllerCount: controllerCount,
      );
    }
    return rate;
  }

  List<_BandSeg> _bandSegments(
    DateTime start,
    DateTime end,
    ActivitySpec activity,
    BusinessCalendar calendar,
  ) {
    if (!end.isAfter(start)) return const [];

    // Non-eligible activities are never split; the whole span is standard.
    if (!activity.happyEligible) {
      return [_BandSeg(UtcInterval(start, end), Band.standard)];
    }

    final boundaries = <DateTime>{start, end};
    var day = IstDate.fromUtc(start);
    final lastDay = IstDate.fromUtc(end);
    while (day.compareTo(lastDay) <= 0) {
      final hw = calendar.happyWindow(day);
      if (hw != null) {
        if (hw.start.isAfter(start) && hw.start.isBefore(end)) {
          boundaries.add(hw.start);
        }
        if (hw.end.isAfter(start) && hw.end.isBefore(end)) {
          boundaries.add(hw.end);
        }
      }
      day = day.addDays(1);
    }

    final sorted = boundaries.toList()..sort();
    final raw = <_BandSeg>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final s = sorted[i];
      final e = sorted[i + 1];
      if (!e.isAfter(s)) continue;
      final midMicros = s.microsecondsSinceEpoch +
          (e.difference(s).inMicroseconds ~/ 2);
      final mid = DateTime.fromMicrosecondsSinceEpoch(midMicros, isUtc: true);
      final band = _isHappyAt(mid, calendar) ? Band.happy : Band.standard;
      raw.add(_BandSeg(UtcInterval(s, e), band));
    }

    // Merge adjacent segments of the same band.
    final merged = <_BandSeg>[];
    for (final seg in raw) {
      if (merged.isNotEmpty && merged.last.band == seg.band) {
        merged[merged.length - 1] = _BandSeg(
          UtcInterval(merged.last.interval.start, seg.interval.end),
          seg.band,
        );
      } else {
        merged.add(seg);
      }
    }
    return merged;
  }

  bool _isHappyAt(DateTime instant, BusinessCalendar calendar) {
    final hw = calendar.happyWindow(IstDate.fromUtc(instant));
    return hw != null && hw.contains(instant);
  }

  // --- segment math ----------------------------------------------------------

  _SegMath _timeCharge(int billedSeconds, Rate rate, BillingPolicy policy) {
    final price = rate.price.value;
    final unitMinutes = rate.unitMinutes;

    if (policy.billingUnit == BillingUnit.perMinute) {
      // Per-second proration of the per-unit price — the truest "actual time".
      final den = unitMinutes * 60;
      final num = price * billedSeconds;
      return _SegMath(
        num: num,
        den: den,
        billedMinutes: roundDivHalfUp(billedSeconds, 60),
        units: 0,
      );
    }

    final block = policy.billingUnit.blockMinutes!;
    final playedMinutesCeil = (billedSeconds + 59) ~/ 60; // whole minutes first
    final billedMinutes = policy.blockRounding == Rounding.up
        ? ceilToStep(playedMinutesCeil, block)
        : roundToStep(playedMinutesCeil, block);
    return _SegMath(
      num: price * billedMinutes,
      den: unitMinutes,
      billedMinutes: billedMinutes,
      units: 0,
    );
  }

  _SegMath _unitCharge(int billedSeconds, Rate rate, BillingPolicy policy) {
    final price = rate.price.value;
    final unitMinutes = rate.unitMinutes;
    final unitSeconds = unitMinutes * 60;

    switch (policy.vrUnitRounding) {
      case VrUnitRounding.prorate:
        return _SegMath(
          num: price * billedSeconds,
          den: unitSeconds,
          billedMinutes: roundDivHalfUp(billedSeconds, 60),
          units: 0,
        );
      case VrUnitRounding.up:
        final units = (billedSeconds + unitSeconds - 1) ~/ unitSeconds;
        return _SegMath(
          num: price * units,
          den: 1,
          billedMinutes: units * unitMinutes,
          units: units,
        );
      case VrUnitRounding.nearest:
        final units = roundDivHalfUp(billedSeconds, unitSeconds);
        return _SegMath(
          num: price * units,
          den: 1,
          billedMinutes: units * unitMinutes,
          units: units,
        );
    }
  }
}

class _BandSeg {
  const _BandSeg(this.interval, this.band);
  final UtcInterval interval;
  final Band band;
}

class _SegMath {
  const _SegMath({
    required this.num,
    required this.den,
    required this.billedMinutes,
    required this.units,
  });
  final int num;
  final int den;
  final int billedMinutes;
  final int units;
}
