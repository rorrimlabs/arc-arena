/// The complete, immutable pricing environment captured when a session starts
/// (spec §31). Everything the pricer needs to be deterministic lives here, so a
/// historical session is re-priced identically forever, regardless of later
/// rate/policy/schedule changes.
library;

import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

@immutable
class PricingSnapshot {
  PricingSnapshot({
    required this.rateCardName,
    required List<Rate> rates,
    required List<ActivitySpec> activities,
    required this.policy,
    required this.hours,
    Set<IstDate> holidays = const {},
    Set<IstDate> closedDays = const {},
  })  : rates = List.unmodifiable(rates),
        activities = {for (final a in activities) a.code: a},
        holidays = Set.unmodifiable(holidays),
        closedDays = Set.unmodifiable(closedDays);

  final String rateCardName;
  final List<Rate> rates;
  final Map<String, ActivitySpec> activities;
  final BillingPolicy policy;
  final BusinessHours hours;
  final Set<IstDate> holidays;

  /// Dates the centre was closed outright (distinct from a trading holiday).
  final Set<IstDate> closedDays;

  BusinessCalendar get calendar => BusinessCalendar(
        hours: hours,
        holidays: holidays,
        closedDays: closedDays,
      );

  ActivitySpec? activity(String code) => activities[code];

  /// Exact rate match for (activity, band, controllerCount). No fallback — the
  /// pricer handles happy→standard fallback.
  Rate? rateFor({
    required String activityCode,
    required Band band,
    required int? controllerCount,
  }) {
    for (final r in rates) {
      if (r.activityCode == activityCode &&
          r.band == band &&
          r.controllerCount == controllerCount) {
        return r;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'rate_card_name': rateCardName,
        'rates': rates.map((r) => r.toJson()).toList(),
        'activities': activities.values.map((a) => a.toJson()).toList(),
        'policy': policy.toJson(),
        'hours': hours.toJson(),
        'holidays': holidays.map((d) => d.iso).toList(),
        'closed_days': closedDays.map((d) => d.iso).toList(),
      };

  factory PricingSnapshot.fromJson(Map<String, dynamic> j) => PricingSnapshot(
        rateCardName: j['rate_card_name'] as String,
        rates: (j['rates'] as List)
            .map((e) => Rate.fromJson(e as Map<String, dynamic>))
            .toList(),
        activities: (j['activities'] as List)
            .map((e) => ActivitySpec.fromJson(e as Map<String, dynamic>))
            .toList(),
        policy: BillingPolicy.fromJson(j['policy'] as Map<String, dynamic>),
        hours: BusinessHours.fromJson(j['hours'] as Map<String, dynamic>),
        holidays: (j['holidays'] as List)
            .map((e) => IstDate.parse(e as String))
            .toSet(),
        // Older snapshots predate explicit closures; absent means "none".
        closedDays: ((j['closed_days'] as List?) ?? const [])
            .map((e) => IstDate.parse(e as String))
            .toSet(),
      );
}
