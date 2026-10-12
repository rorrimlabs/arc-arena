/// The output of the pricing engine: a breakdown plus the final amount.
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

/// One priced stretch of time within a session (e.g. the happy-hour portion).
@immutable
class PricingSegment {
  const PricingSegment({
    required this.interval,
    required this.band,
    required this.playedSeconds,
    required this.billedMinutes,
    required this.units,
    required this.unitMinutes,
    required this.unitPrice,
    required this.amount,
    required this.rawNumerator,
    required this.rawDenominator,
  });

  final UtcInterval interval;
  final Band band;

  /// Wall-clock seconds actually played in this segment.
  final int playedSeconds;

  /// Minutes this segment is billed for (after block rounding). For unit
  /// activities this equals units * unitMinutes.
  final int billedMinutes;

  /// Whole units charged (unit activities like VR). For time-based activities
  /// this is 0 and [billedMinutes] is authoritative.
  final int units;

  final int unitMinutes;
  final Paise unitPrice;

  /// This segment's amount, rounded to paise for display.
  final Paise amount;

  /// Exact amount = rawNumerator / rawDenominator paise. Used so the session can
  /// round once at the end when rounding scope is `session`.
  final int rawNumerator;
  final int rawDenominator;

  int get playedMinutes => playedSeconds ~/ 60;
}

@immutable
class PricingQuote {
  const PricingQuote({
    required this.segments,
    required this.playedSeconds,
    required this.billedMinutes,
    required this.subtotal,
    required this.amount,
  });

  final List<PricingSegment> segments;

  /// Total wall-clock seconds from start to end.
  final int playedSeconds;

  /// Total billed minutes across segments.
  final int billedMinutes;

  /// Amount before final cash rounding.
  final Paise subtotal;

  /// Final payable amount after cash rounding.
  final Paise amount;

  int get playedMinutes => playedSeconds ~/ 60;

  /// Difference introduced by cash rounding (can be negative).
  Paise get roundingAdjustment => amount - subtotal;

  bool get isFree => amount.isZero;
}
