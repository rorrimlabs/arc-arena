/// Bills a group session from its assignments (group feature §9). Pure.
///
/// Two owner-confirmed modes (OWNER CONFIRMATION #24):
///
///  * [GroupBillingMode.perSystem] (default): each SYSTEM is billed for the time
///    the group uses it, at the rate for the number of controllers on that
///    system AT THAT TIME. A sweep over each resource's assignments splits its
///    timeline wherever the controller count changes (a player joins or leaves),
///    so two players sharing one PS5 are billed once at the 2-controller rate,
///    while three players on three systems are billed as three systems. A
///    three-controller price is never silently stretched to cover three systems.
///
///  * [GroupBillingMode.sharedControllerPool]: the purchased controllers are
///    billed once at the single-system multi-controller rate for the whole group
///    window, regardless of how many systems they are spread across. Any
///    non-controller usage (VR, pool, lounge) is still billed per system.
///
/// Subtotals are summed in paise and cash rounding is applied ONCE to the group
/// total, exactly like [SegmentBilling] for a single session.
///
/// Pricing rules are judged once, at the GROUP's start, for every stretch
/// (`_pr_group_bill`, `_pr_sweep`).
///
/// SERVER PARITY: the server re-prices every bill with a plpgsql port of this
/// code (migration 0013, `_pr_*`) and refuses any difference. Changing how
/// money is computed here needs a matching new migration and a green
/// Dart-vs-SQL parity check — see docs/SYNC.md "Changing pricing".
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rounding.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_rule.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

@immutable
class GroupBill {
  const GroupBill({
    required this.total,
    required this.subtotal,
    required this.charges,
    this.rules = const [],
  });

  /// Final payable amount after cash rounding.
  final Paise total;

  /// Sum of all sub-charge subtotals before cash rounding.
  final Paise subtotal;

  /// Immutable charge rows (one per priced stretch).
  final List<GroupCharge> charges;

  /// The pricing rules that adjusted this bill's prices, without repeats.
  final List<PricingRule> rules;
}

class GroupBilling {
  const GroupBilling({this.pricing = const PricingService()});
  final PricingService pricing;

  /// Prices [assignments]. Open assignments (endedAt == null) are priced up to
  /// [openEndAt] (now for a live amount, or the actual end at close). The pooled
  /// mode bills purchased controllers over `[groupStart, openEndAt]`.
  /// [groupStart] is also the pricing-rule instant for every stretch.
  /// [billUntil] (the booked end when overtime is not charged) caps every
  /// window and the pool. Port: `_pr_group_bill` / `_pr_sweep` (p_until).
  GroupBill bill({
    required PricingSnapshot snapshot,
    required List<GroupAssignment> assignments,
    required GroupBillingMode mode,
    required int purchasedControllerCount,
    required DateTime groupStart,
    required DateTime openEndAt,
    DateTime? billUntil,
  }) {
    DateTime capped(DateTime t) =>
        billUntil != null && t.isAfter(billUntil) ? billUntil : t;
    final groupId = assignments.isEmpty ? '' : assignments.first.groupId;
    final charges = <GroupCharge>[];
    final rules = <PricingRule>{};
    var subtotal = 0;
    var index = 0;

    void addQuote(
      PricingQuote q, {
      required String activityCode,
      String? resourceId,
      int? controllerCount,
      int? playerNumber,
      String? assignmentId,
    }) {
      subtotal += q.subtotal.value;
      if (q.rule != null) rules.add(q.rule!);
      for (final ps in q.segments) {
        charges.add(GroupCharge(
          id: '',
          groupId: groupId,
          assignmentId: assignmentId,
          playerNumber: playerNumber,
          chargeIndex: index++,
          bandCode: ps.band.code,
          activityCode: activityCode,
          resourceId: resourceId,
          controllerCount: controllerCount,
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

    // Sweep one resource's assignments, splitting at every controller-count
    // change, and bill each constant-controller stretch at its combined rate.
    void sweepResource(String resourceId, List<GroupAssignment> list) {
      final windows = <({GroupAssignment a, DateTime start, DateTime end})>[
        for (final a in list)
          (a: a, start: a.startedAt, end: capped(a.endedAt ?? openEndAt)),
      ].where((w) => w.end.isAfter(w.start)).toList();
      if (windows.isEmpty) return;

      final points = <DateTime>{};
      for (final w in windows) {
        points..add(w.start)..add(w.end);
      }
      final sorted = points.toList()..sort();

      for (var i = 0; i < sorted.length - 1; i++) {
        final s = sorted[i];
        final e = sorted[i + 1];
        if (!e.isAfter(s)) continue;
        final active = [
          for (final w in windows)
            if (!w.start.isAfter(s) && !w.end.isBefore(e)) w.a,
        ];
        if (active.isEmpty) continue;

        final controllers =
            active.fold<int>(0, (sum, a) => sum + (a.controllerCount ?? 0));
        final activityCode = active.first.activityCode;
        final quoted = pricing.quote(
          snapshot: snapshot,
          activityCode: activityCode,
          controllerCount: controllers == 0 ? null : controllers,
          start: s,
          end: e,
          ruleAt: groupStart,
        );
        final q = quoted.valueOrNull;
        if (q == null) continue; // misconfigured rate; excluded from the bill
        final single = active.length == 1;
        addQuote(
          q,
          activityCode: activityCode,
          resourceId: resourceId,
          controllerCount: controllers == 0 ? null : controllers,
          playerNumber: single ? active.first.playerNumber : null,
          assignmentId: single ? active.first.id : null,
        );
      }
    }

    switch (mode) {
      case GroupBillingMode.perSystem:
        final byResource = <String, List<GroupAssignment>>{};
        for (final a in assignments) {
          (byResource[a.resourceId] ??= []).add(a);
        }
        byResource.forEach(sweepResource);

      case GroupBillingMode.sharedControllerPool:
        // Pool the purchased controllers into one charge over the whole window.
        final pooled =
            assignments.where((a) => a.controllerCount != null).toList();
        if (purchasedControllerCount > 0 &&
            pooled.isNotEmpty &&
            capped(openEndAt).isAfter(groupStart)) {
          final activityCode = pooled.first.activityCode;
          final quoted = pricing.quote(
            snapshot: snapshot,
            activityCode: activityCode,
            controllerCount: purchasedControllerCount,
            start: groupStart,
            end: capped(openEndAt),
            ruleAt: groupStart,
          );
          final q = quoted.valueOrNull;
          if (q != null) {
            addQuote(
              q,
              activityCode: activityCode,
              controllerCount: purchasedControllerCount,
            );
          }
        }
        // Everything without controllers (VR/pool/lounge) is billed per system.
        final rest = <String, List<GroupAssignment>>{};
        for (final a in assignments.where((a) => a.controllerCount == null)) {
          (rest[a.resourceId] ??= []).add(a);
        }
        rest.forEach(sweepResource);
    }

    final total = applyMoneyRounding(
      subtotal,
      snapshot.policy.moneyRoundingPaise,
      snapshot.policy.moneyRoundingDir,
    );
    return GroupBill(
      total: Paise(total),
      subtotal: Paise(subtotal),
      charges: charges,
      rules: rules.toList(),
    );
  }
}
