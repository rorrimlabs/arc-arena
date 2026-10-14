import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/pricing_rule.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';

/// Builds the center's current rate card (mirrors supabase/seed.sql), with
/// [rules] (none by default).
PricingSnapshot currentSnapshot({
  BillingPolicy? policy,
  Set<IstDate> holidays = const {},
  List<PricingRule> rules = const [],
}) {
  final activities = <ActivitySpec>[
    const ActivitySpec(code: 'PS5', durationModel: DurationModel.hourly),
    const ActivitySpec(code: 'VR', durationModel: DurationModel.unit),
    const ActivitySpec(code: 'POOL', durationModel: DurationModel.hourly),
    const ActivitySpec(code: 'LOUNGE', durationModel: DurationModel.flatHourly),
  ];

  Rate ps5(int controllers, Band band, int paise) => Rate(
        activityCode: 'PS5',
        band: band,
        controllerCount: controllers,
        unitMinutes: 60,
        price: Paise(paise),
      );

  final rates = <Rate>[
    ps5(1, Band.standard, 15000),
    ps5(2, Band.standard, 28000),
    ps5(3, Band.standard, 39000),
    ps5(4, Band.standard, 48000),
    const Rate(activityCode: 'VR', band: Band.standard, controllerCount: null, unitMinutes: 30, price: Paise(20000)),
    const Rate(activityCode: 'POOL', band: Band.standard, controllerCount: null, unitMinutes: 60, price: Paise(27500)),
    const Rate(activityCode: 'LOUNGE', band: Band.standard, controllerCount: null, unitMinutes: 60, price: Paise(200000)),
  ];

  return PricingSnapshot(
    rateCardName: 'Current',
    rates: rates,
    activities: activities,
    policy: policy ?? BillingPolicy.defaults,
    hours: BusinessHours.current(),
    holidays: holidays,
    rules: rules,
  );
}

/// The demo seed's afternoon rule: Tue–Fri 14:00–17:00 IST, not on a holiday,
/// −20% on PS5 and Pool (₹150 → ₹120, ₹275 → ₹220).
PricingRule afternoonRule({
  String id = 'r1',
  String name = 'Afternoon deal',
  int priority = 1,
  List<int> days = const [2, 3, 4, 5],
  int startMin = 14 * 60,
  int endMin = 17 * 60,
  RuleHolidayMode holidayMode = RuleHolidayMode.skip,
  IstDate? validFrom,
  IstDate? validUntil,
  List<String> activityCodes = const ['PS5', 'POOL'],
  RuleAdjustKind adjustKind = RuleAdjustKind.percent,
  int adjustValue = -20,
}) =>
    PricingRule(
      id: id,
      name: name,
      priority: priority,
      days: days,
      startMin: startMin,
      endMin: endMin,
      holidayMode: holidayMode,
      validFrom: validFrom,
      validUntil: validUntil,
      activityCodes: activityCodes,
      adjustKind: adjustKind,
      adjustValue: adjustValue,
    );

/// A UTC instant from an IST wall-clock time.
DateTime ist(int y, int mo, int d, int h, int mi) =>
    IstTime(y, mo, d, h, mi).toUtc();

// Reference dates (verified weekdays):
//   Friday    2026-10-02  → inside [afternoonRule]'s days (Tue–Fri)
//   Saturday  2026-10-03  → weekend
//   Sunday    2026-10-04  → weekend
//   Monday    2026-10-05  → CLOSED (the arena trades Tue–Sun)
//   Tuesday   2026-10-06  → inside [afternoonRule]'s days (Tue–Fri)
final DateTime friday2pm = ist(2026, 10, 2, 14, 0);
final IstDate fridayDate = const IstDate(2026, 10, 2);
final IstDate saturdayDate = const IstDate(2026, 10, 3);
final IstDate sundayDate = const IstDate(2026, 10, 4);
final IstDate mondayDate = const IstDate(2026, 10, 5);
final IstDate tuesdayDate = const IstDate(2026, 10, 6);
