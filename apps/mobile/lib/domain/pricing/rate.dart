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
    this.overtimeGraceMinutes = 0,
  });

  final String code; // PS5 | VR | POOL | LOUNGE
  final DurationModel durationModel;

  /// Overtime allowed free past a session's booked end when it ends on this
  /// type (see `overtimeBillUntil`). 0 = every overtime minute is billed.
  final int overtimeGraceMinutes;

  /// Same keys as the server's `_pricing_snapshot` activities.
  Map<String, dynamic> toJson() => {
        'code': code,
        'duration_model': durationModel.code,
        'overtime_grace_minutes': overtimeGraceMinutes,
      };

  /// Snapshots frozen by older builds carry an extra activity flag; it is
  /// ignored (nothing prices by it any more).
  factory ActivitySpec.fromJson(Map<String, dynamic> j) => ActivitySpec(
        code: j['code'] as String,
        durationModel: DurationModel.fromCode(j['duration_model'] as String),
        // Snapshots frozen before the overtime grace existed: none.
        overtimeGraceMinutes: (j['overtime_grace_minutes'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is ActivitySpec &&
      other.code == code &&
      other.durationModel == durationModel &&
      other.overtimeGraceMinutes == overtimeGraceMinutes;

  @override
  int get hashCode => Object.hash(code, durationModel, overtimeGraceMinutes);
}

/// A price for a given activity + band + (optional) controller count. The
/// pricer only ever reads [Band.standard] rates.
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

  /// [Rate.fromJson], or null for a rate of a retired band (never priced).
  static Rate? tryFromJson(Map<String, dynamic> j) =>
      Band.tryFromCode(j['band'] as String) == null ? null : Rate.fromJson(j);

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
