/// The configurable billing rules (every OWNER CONFIRMATION knob from §6).
///
/// Defaults are the documented assumptions in docs/OWNER_CONFIRMATION.md — safe,
/// explicit, and changeable by the owner later with no code change. This object
/// is captured into each session's immutable snapshot (spec §31).
library;

import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

@immutable
class BillingPolicy {
  const BillingPolicy({
    this.billingUnit = BillingUnit.perMinute, // #1
    this.blockRounding = Rounding.up, // #2
    this.graceMinutes = 0, // #3
    this.minimumChargeMinutes = 0, // #4
    this.earlyExit = EarlyExit.actual, // #5
    this.roundingScope = RoundingScope.session, // #7
    this.lateArrival = LateArrival.actual, // #8
    this.vrUnitRounding = VrUnitRounding.up, // #12
    this.moneyRoundingPaise = 100, // #16 → nearest ₹1
    this.moneyRoundingDir = MoneyRoundingDir.nearest, // #16
    this.paymentTiming = PaymentTiming.either, // #17
    this.allowExtendPastClose = false, // #18
    this.cleaningGapMinutes = 0, // #23
    this.groupBillingMode = GroupBillingMode.perSystem, // #24
    this.overtimeGraceMinutes = 0,
  });

  /// The documented MVP defaults.
  static const BillingPolicy defaults = BillingPolicy();

  final BillingUnit billingUnit;
  final Rounding blockRounding;
  final int graceMinutes;
  final int minimumChargeMinutes;
  final EarlyExit earlyExit;
  final RoundingScope roundingScope;
  final LateArrival lateArrival;
  final VrUnitRounding vrUnitRounding;

  /// Round the final cash total to this many paise (100 = ₹1, 500 = ₹5).
  final int moneyRoundingPaise;
  final MoneyRoundingDir moneyRoundingDir;

  final PaymentTiming paymentTiming;
  final bool allowExtendPastClose;
  final int cleaningGapMinutes;

  /// How a group spanning several systems is billed (group feature §9).
  final GroupBillingMode groupBillingMode;

  /// Overtime allowed free past a single session's booked end (0–240 min):
  /// ended within it, the session is billed to its booked end; past it, the
  /// whole actual time is billed. 0 = every overtime minute is billed.
  /// Applied by [SegmentBilling] through `overtimeBillUntil` and on the
  /// server by `_pr_session_bill`.
  final int overtimeGraceMinutes;

  BillingPolicy copyWith({
    BillingUnit? billingUnit,
    Rounding? blockRounding,
    int? graceMinutes,
    int? minimumChargeMinutes,
    EarlyExit? earlyExit,
    RoundingScope? roundingScope,
    LateArrival? lateArrival,
    VrUnitRounding? vrUnitRounding,
    int? moneyRoundingPaise,
    MoneyRoundingDir? moneyRoundingDir,
    PaymentTiming? paymentTiming,
    bool? allowExtendPastClose,
    int? cleaningGapMinutes,
    GroupBillingMode? groupBillingMode,
    int? overtimeGraceMinutes,
  }) =>
      BillingPolicy(
        billingUnit: billingUnit ?? this.billingUnit,
        blockRounding: blockRounding ?? this.blockRounding,
        graceMinutes: graceMinutes ?? this.graceMinutes,
        minimumChargeMinutes: minimumChargeMinutes ?? this.minimumChargeMinutes,
        earlyExit: earlyExit ?? this.earlyExit,
        roundingScope: roundingScope ?? this.roundingScope,
        lateArrival: lateArrival ?? this.lateArrival,
        vrUnitRounding: vrUnitRounding ?? this.vrUnitRounding,
        moneyRoundingPaise: moneyRoundingPaise ?? this.moneyRoundingPaise,
        moneyRoundingDir: moneyRoundingDir ?? this.moneyRoundingDir,
        paymentTiming: paymentTiming ?? this.paymentTiming,
        allowExtendPastClose: allowExtendPastClose ?? this.allowExtendPastClose,
        cleaningGapMinutes: cleaningGapMinutes ?? this.cleaningGapMinutes,
        groupBillingMode: groupBillingMode ?? this.groupBillingMode,
        overtimeGraceMinutes: overtimeGraceMinutes ?? this.overtimeGraceMinutes,
      );

  Map<String, dynamic> toJson() => {
        'billing_unit': billingUnit.code,
        'block_rounding': blockRounding.code,
        'grace_minutes': graceMinutes,
        'minimum_charge_minutes': minimumChargeMinutes,
        'early_exit': earlyExit.code,
        'rounding_scope': roundingScope.code,
        'late_arrival': lateArrival.code,
        'vr_unit_rounding': vrUnitRounding.code,
        'money_rounding_paise': moneyRoundingPaise,
        'money_rounding_dir': moneyRoundingDir.code,
        'payment_timing': paymentTiming.code,
        'allow_extend_past_close': allowExtendPastClose,
        'cleaning_gap_minutes': cleaningGapMinutes,
        'group_billing_mode': groupBillingMode.code,
        'overtime_grace_minutes': overtimeGraceMinutes,
      };

  factory BillingPolicy.fromJson(Map<String, dynamic> j) => BillingPolicy(
        billingUnit: BillingUnit.fromCode(j['billing_unit'] as String),
        blockRounding: Rounding.fromCode(j['block_rounding'] as String),
        graceMinutes: j['grace_minutes'] as int,
        minimumChargeMinutes: j['minimum_charge_minutes'] as int,
        earlyExit: EarlyExit.fromCode(j['early_exit'] as String),
        roundingScope: RoundingScope.fromCode(j['rounding_scope'] as String),
        lateArrival: LateArrival.fromCode(j['late_arrival'] as String),
        vrUnitRounding: VrUnitRounding.fromCode(j['vr_unit_rounding'] as String),
        moneyRoundingPaise: j['money_rounding_paise'] as int,
        moneyRoundingDir: MoneyRoundingDir.fromCode(j['money_rounding_dir'] as String),
        paymentTiming: PaymentTiming.fromCode(j['payment_timing'] as String),
        allowExtendPastClose: j['allow_extend_past_close'] as bool,
        cleaningGapMinutes: j['cleaning_gap_minutes'] as int,
        // Tolerate snapshots captured before the group knob existed.
        groupBillingMode: j['group_billing_mode'] == null
            ? GroupBillingMode.perSystem
            : GroupBillingMode.fromCode(j['group_billing_mode'] as String),
        // Snapshots captured before the overtime grace existed: no grace.
        overtimeGraceMinutes: (j['overtime_grace_minutes'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is BillingPolicy &&
      other.billingUnit == billingUnit &&
      other.blockRounding == blockRounding &&
      other.graceMinutes == graceMinutes &&
      other.minimumChargeMinutes == minimumChargeMinutes &&
      other.earlyExit == earlyExit &&
      other.roundingScope == roundingScope &&
      other.lateArrival == lateArrival &&
      other.vrUnitRounding == vrUnitRounding &&
      other.moneyRoundingPaise == moneyRoundingPaise &&
      other.moneyRoundingDir == moneyRoundingDir &&
      other.paymentTiming == paymentTiming &&
      other.allowExtendPastClose == allowExtendPastClose &&
      other.cleaningGapMinutes == cleaningGapMinutes &&
      other.groupBillingMode == groupBillingMode &&
      other.overtimeGraceMinutes == overtimeGraceMinutes;

  @override
  int get hashCode => Object.hashAll([
        billingUnit,
        blockRounding,
        graceMinutes,
        minimumChargeMinutes,
        earlyExit,
        roundingScope,
        lateArrival,
        vrUnitRounding,
        moneyRoundingPaise,
        moneyRoundingDir,
        paymentTiming,
        allowExtendPastClose,
        cleaningGapMinutes,
        groupBillingMode,
        overtimeGraceMinutes,
      ]);
}
