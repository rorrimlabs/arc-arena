/// Pricing rules: which rule applies, and what it does to a unit price. PURE.
///
/// SERVER PARITY: exact ports of `_pr_rule` and `_pr_rule_price`
/// (supabase/schemas/public/functions/). The server re-prices every bill and
/// refuses any difference — change both sides together and check
/// parity (docs/SYNC.md "Changing pricing").
library;

import 'package:arena_ops/core/money/rounding.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/pricing/pricing_rule.dart';
import 'package:arena_ops/domain/value/enums.dart';

/// The minute of the IST day a rule judges [instant] at, as `_pr_rule` does:
/// the whole minutes since IST midnight, seconds dropped. So 13:59:59 IST is
/// minute 839 (before a 14:00 rule) and 16:59:59 is 1019 (inside one that
/// ends at 17:00).
int ruleMinuteOfDay(DateTime instant) {
  final local = instant.toUtc().add(istOffset);
  return local.hour * 60 + local.minute;
}

/// Whether [rule] applies to [activityCode] started at [at] (`_pr_rule`):
/// the IST weekday is in `days`, the minute of day in `[startMin, endMin)`,
/// the IST date inside `[validFrom, validUntil]`, the holiday mode holds
/// against [holidays], and the activity is listed (empty list = every one).
bool ruleApplies(
  PricingRule rule, {
  required String activityCode,
  required DateTime at,
  required Set<IstDate> holidays,
}) {
  final date = IstDate.fromUtc(at.toUtc());
  final minute = ruleMinuteOfDay(at);
  if (!rule.days.contains(date.weekday)) return false;
  if (minute < rule.startMin || minute >= rule.endMin) return false;
  final from = rule.validFrom;
  if (from != null && date.compareTo(from) < 0) return false;
  final until = rule.validUntil;
  if (until != null && date.compareTo(until) > 0) return false;
  final holiday = holidays.contains(date);
  switch (rule.holidayMode) {
    case RuleHolidayMode.only:
      if (!holiday) return false;
    case RuleHolidayMode.skip:
      if (holiday) return false;
    case RuleHolidayMode.any:
      break;
  }
  return rule.activityCodes.isEmpty || rule.activityCodes.contains(activityCode);
}

/// The rule that prices [activityCode] started at [at]: the first applying
/// rule by priority, then name, then id; null when none applies.
PricingRule? matchRule(
  Iterable<PricingRule> rules, {
  required String activityCode,
  required DateTime at,
  required Set<IstDate> holidays,
}) {
  PricingRule? best;
  for (final r in rules) {
    if (!ruleApplies(r, activityCode: activityCode, at: at, holidays: holidays)) {
      continue;
    }
    if (best == null || compareRuleOrder(r, best) < 0) best = r;
  }
  return best;
}

/// Rule order: priority, then name, then id (`order by priority, name, id`,
/// names and ids compared by code point: the server's `collate "C"`).
int compareRuleOrder(PricingRule a, PricingRule b) {
  final p = a.priority.compareTo(b.priority);
  if (p != 0) return p;
  final n = a.name.compareTo(b.name);
  if (n != 0) return n;
  return a.id.compareTo(b.id);
}

/// A rate's unit price in paise after [rule] (`_pr_rule_price`); [price]
/// unchanged when [rule] is null. Never below 0.
///
///  * percent: round-half-up(price × (100 + value) / 100) — `_pr_div`.
///  * per_hour: price + floor((2 · value · unitMinutes + 60) / 120), i.e.
///    value × unitMinutes / 60 rounded half toward +∞, for discounts too.
int applyRulePrice(int price, int unitMinutes, PricingRule? rule) {
  if (rule == null) return price;
  final int adjusted;
  switch (rule.adjustKind) {
    case RuleAdjustKind.percent:
      // adjust_value >= −100, so the numerator is never negative.
      final scaled = price * (100 + rule.adjustValue);
      adjusted = scaled <= 0 ? 0 : roundDivHalfUp(scaled, 100);
    case RuleAdjustKind.perHour:
      adjusted = price + _floorDiv(2 * rule.adjustValue * unitMinutes + 60, 120);
  }
  return adjusted < 0 ? 0 : adjusted;
}

/// Floor division for a positive [d] (Dart's `~/` truncates toward zero).
int _floorDiv(int n, int d) => (n - n % d) ~/ d;
