/// Bills a parent session from ALL its segments (spec §14). Each segment keeps
/// its own system/game/controller config and is priced over its own time window
/// with the parent's immutable snapshot. Pure.
///
/// Segment subtotals are summed in paise and the final cash rounding is applied
/// ONCE to the session total, so switching mid-session never changes the money
/// rounding behaviour versus a single continuous session.
///
/// SERVER PARITY: the server re-prices every bill with a plpgsql port of this
/// code (migration 0013, `_pr_*`) and refuses any difference. Changing how
/// money is computed here needs a matching new migration and a green
/// `bash tool/pricing_parity.sh` — see docs/SYNC.md "Changing pricing".
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rounding.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:meta/meta.dart';

/// A segment the rate card could not price, with the reason why.
@immutable
class UnpricedSegment {
  const UnpricedSegment({required this.segment, required this.reason});
  final SessionSegment segment;
  final String reason;
}

@immutable
class SegmentLine {
  const SegmentLine({required this.segment, required this.quote});
  final SessionSegment segment;
  final PricingQuote quote;
}

@immutable
class SegmentBill {
  const SegmentBill({
    required this.total,
    required this.subtotal,
    required this.charges,
    required this.lines,
    this.unpriced = const [],
  });

  /// Segments that could not be priced (no rate configured for that
  /// activity/controller combination). They contribute **nothing** to the
  /// total, so staff must be told rather than silently under-charging.
  final List<UnpricedSegment> unpriced;

  /// True when at least one segment has no configured rate, so [total] is
  /// lower than the time actually played.
  bool get isIncomplete => unpriced.isNotEmpty;

  /// Final payable amount after cash rounding.
  final Paise total;

  /// Sum of segment subtotals before cash rounding.
  final Paise subtotal;

  /// Immutable charge rows (one per happy-hour sub-segment of each segment).
  final List<SessionCharge> charges;

  /// Per-segment quotes, for the session-history / end breakdown.
  final List<SegmentLine> lines;

  Duration get played =>
      lines.fold(Duration.zero, (d, l) => d + Duration(seconds: l.quote.playedSeconds));
}

class SegmentBilling {
  const SegmentBilling({this.pricing = const PricingService()});
  final PricingService pricing;

  /// Prices [segments]. The open segment (endedAt == null) is priced up to
  /// [openEndAt] (usually `now` for a live amount, or the actual end at close).
  SegmentBill bill({
    required PricingSnapshot snapshot,
    required List<SessionSegment> segments,
    required DateTime openEndAt,
  }) {
    final lines = <SegmentLine>[];
    final charges = <SessionCharge>[];
    final unpriced = <UnpricedSegment>[];
    var subtotal = 0;
    var chargeIndex = 0;

    for (final seg in segments) {
      final end = seg.endedAt ?? openEndAt;
      final quoted = pricing.quote(
        snapshot: snapshot,
        activityCode: seg.activityCode,
        controllerCount: seg.controllerCount,
        start: seg.startedAt,
        end: end,
      );
      final q = quoted.valueOrNull;
      if (q == null) {
        // No rate for this combination. Record it so the End screen can warn
        // instead of quietly handing the customer a short bill.
        unpriced.add(UnpricedSegment(
          segment: seg,
          reason: quoted.failureOrNull?.message ??
              'No price is configured for this combination.',
        ));
        continue;
      }
      subtotal += q.subtotal.value;
      lines.add(SegmentLine(segment: seg, quote: q));
      for (final ps in q.segments) {
        charges.add(SessionCharge(
          id: '',
          sessionId: seg.sessionId,
          segmentId: seg.id,
          segmentIndex: chargeIndex++,
          bandCode: ps.band.code,
          activityCode: seg.activityCode,
          resourceId: seg.resourceId,
          controllerCount: seg.controllerCount,
          segmentStart: ps.interval.start,
          segmentEnd: ps.interval.end,
          playedMinutes: ps.playedMinutes,
          billedMinutes: ps.billedMinutes,
          unitMinutes: ps.unitMinutes,
          unitPricePaise: ps.unitPrice.value,
          amountPaise: ps.amount.value,
        ));
      }
    }

    final total = applyMoneyRounding(
      subtotal,
      snapshot.policy.moneyRoundingPaise,
      snapshot.policy.moneyRoundingDir,
    );
    return SegmentBill(
      total: Paise(total),
      subtotal: Paise(subtotal),
      charges: charges,
      lines: lines,
      unpriced: unpriced,
    );
  }
}
