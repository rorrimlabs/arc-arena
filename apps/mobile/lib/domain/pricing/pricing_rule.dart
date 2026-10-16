/// A pricing rule: a day/time price adjustment on top of the rate card
/// ("Weekday afternoons −20%", "Weekend evenings +₹50/h"). The owner defines rules on
/// the admin dashboard (server table `pricing_rules`); the floor app only reads
/// them. Active rules are frozen into every new session's [PricingSnapshot].
///
/// Matching and the price change live in `rule_engine.dart`.
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pricing_rule.freezed.dart';

@freezed
abstract class PricingRule with _$PricingRule {
  const PricingRule._();

  const factory PricingRule({
    required String id,
    required String name,

    /// Lower wins when several rules match; ties by [name], then [id].
    required int priority,

    /// ISO weekdays (1 = Monday … 7 = Sunday) of the IST date of the start.
    required List<int> days,

    /// Window in minutes after IST midnight, `[startMin, endMin)`.
    required int startMin,
    required int endMin,
    @Default(RuleHolidayMode.any) RuleHolidayMode holidayMode,

    /// First / last IST date the rule applies (inclusive); null = open-ended.
    IstDate? validFrom,
    IstDate? validUntil,

    /// Activity codes the rule applies to; empty = every activity.
    @Default(<String>[]) List<String> activityCodes,
    required RuleAdjustKind adjustKind,

    /// Signed: percent (−100…500) or paise per hour.
    required int adjustValue,
  }) = _PricingRule;

  /// Same keys and value shapes as the server's `_pricing_snapshot` rules.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priority': priority,
        'days': days,
        'start_min': startMin,
        'end_min': endMin,
        'holiday_mode': holidayMode.code,
        'valid_from': validFrom?.iso,
        'valid_until': validUntil?.iso,
        'activity_codes': activityCodes,
        'adjust_kind': adjustKind.code,
        'adjust_value': adjustValue,
      };

  /// Reads a snapshot rule, or a `pricing_rules` row from the sync feed
  /// (same column names; extra columns are ignored).
  static PricingRule fromJson(Map<String, dynamic> j) => PricingRule(
        id: j['id'] as String,
        name: j['name'] as String,
        priority: (j['priority'] as num).toInt(),
        days: [for (final d in j['days'] as List) (d as num).toInt()],
        startMin: (j['start_min'] as num).toInt(),
        endMin: (j['end_min'] as num).toInt(),
        holidayMode:
            RuleHolidayMode.fromCode((j['holiday_mode'] as String?) ?? 'any'),
        validFrom: _date(j['valid_from']),
        validUntil: _date(j['valid_until']),
        activityCodes: [
          for (final c in (j['activity_codes'] as List?) ?? const []) c as String,
        ],
        adjustKind: RuleAdjustKind.fromCode(j['adjust_kind'] as String),
        adjustValue: (j['adjust_value'] as num).toInt(),
      );

  static IstDate? _date(Object? v) => v == null ? null : IstDate.parse(v as String);

  /// The adjustment for a price line, e.g. "−20%" or "+₹50/h".
  String get adjustmentLabel {
    final sign = adjustValue < 0 ? '−' : '+';
    return switch (adjustKind) {
      RuleAdjustKind.percent => '$sign${adjustValue.abs()}%',
      RuleAdjustKind.perHour => '$sign${Paise(adjustValue.abs()).display}/h',
    };
  }

  /// "Weekday afternoons −20%".
  String get summary => '$name $adjustmentLabel';
}
