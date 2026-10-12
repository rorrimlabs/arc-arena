/// A single rate row and the minimal activity metadata the pricer needs.
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

/// Pricing-relevant facts about an activity.
@immutable
class ActivitySpec {
  const ActivitySpec({
    required this.code,
    required this.durationModel,
    required this.happyEligible,
  });

  final String code; // PS5 | VR | POOL | LOUNGE
  final DurationModel durationModel;

  /// Whether happy-hour rates ever apply to this activity (OWNER #10/#11).
  final bool happyEligible;

  Map<String, dynamic> toJson() => {
        'code': code,
        'duration_model': durationModel.code,
        'happy_eligible': happyEligible,
      };

  factory ActivitySpec.fromJson(Map<String, dynamic> j) => ActivitySpec(
        code: j['code'] as String,
        durationModel: DurationModel.fromCode(j['duration_model'] as String),
        happyEligible: j['happy_eligible'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is ActivitySpec &&
      other.code == code &&
      other.durationModel == durationModel &&
      other.happyEligible == happyEligible;

  @override
  int get hashCode => Object.hash(code, durationModel, happyEligible);
}

/// A price for a given activity + band + (optional) controller count.
///
/// [unitMinutes] is the length of one priced unit: 60 for hourly rates, 30 for
/// VR. [price] is the money for exactly one unit.
@immutable
class Rate {
  const Rate({
    required this.activityCode,
    required this.band,
    required this.controllerCount,
    required this.unitMinutes,
    required this.price,
  });

  final String activityCode;
  final Band band;
  final int? controllerCount; // null for non-controller activities
  final int unitMinutes;
  final Paise price;

  Map<String, dynamic> toJson() => {
        'activity_code': activityCode,
        'band': band.code,
        'controller_count': controllerCount,
        'unit_minutes': unitMinutes,
        'price_paise': price.value,
      };

  factory Rate.fromJson(Map<String, dynamic> j) => Rate(
        activityCode: j['activity_code'] as String,
        band: Band.fromCode(j['band'] as String),
        controllerCount: j['controller_count'] as int?,
        unitMinutes: j['unit_minutes'] as int,
        price: Paise(j['price_paise'] as int),
      );

  @override
  bool operator ==(Object other) =>
      other is Rate &&
      other.activityCode == activityCode &&
      other.band == band &&
      other.controllerCount == controllerCount &&
      other.unitMinutes == unitMinutes &&
      other.price == price;

  @override
  int get hashCode =>
      Object.hash(activityCode, band, controllerCount, unitMinutes, price);
}
