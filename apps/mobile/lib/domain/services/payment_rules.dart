/// The sign convention for money rows, enforced in one place.
///
/// Takings are summed straight off the payment rows — `sum(amountPaise)` is
/// what the session owes against, what Money shows and what the day's report
/// collects. That only works if a payment is positive and a refund is negative.
///
/// Nothing used to enforce it, which let two wrong rows through: a refund saved
/// as a positive amount (which *raises* takings and marks a session more paid
/// than it is) and a payment saved as a negative amount (money out without the
/// reason a refund requires, and without the discount permission a refund
/// needs). Both are repaired here, at the only door the repositories use.
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rounding.dart';
import 'package:arena_ops/core/result/result.dart';

/// Normalises [amountPaise] for storage, or explains why it cannot be stored.
///
/// A refund is stored negative whichever sign the caller passed, so the row is
/// right even when a call site gets it wrong. A payment must be positive: a
/// negative one would be a refund in disguise, skipping its checks.
Result<int> signedPaymentAmount(int amountPaise, {required bool isRefund}) {
  if (amountPaise == 0) {
    return const Err(Failure(
      message: 'Enter an amount.',
      fix: 'A zero payment has nothing to record.',
      code: 'amount_zero',
    ));
  }
  if (isRefund) return Ok(-amountPaise.abs());
  if (amountPaise < 0) {
    return const Err(Failure(
      message: 'A payment cannot be a negative amount.',
      fix: 'To give money back, record a refund with a reason.',
      code: 'amount_negative',
    ));
  }
  return Ok(amountPaise);
}

/// Whether a payment of [signed] paise (negative = refund) fits the balance.
///
/// Two people can each see "₹300 remaining" — on two devices before either
/// syncs, or a running-session advance followed by the full bill at the end —
/// and each record it. Without this the bill is collected twice and Money and
/// Reports show takings that never existed. So, once a bill is final, payments
/// may only fill it up to the bill, and a refund may never give back more than
/// was collected. While a session runs there is no final bill yet, so advance
/// payments are not capped. A waived bill keeps its old behaviour.
///
/// The server applies the same rule in `op_payment` (migration 0016): a
/// payment this device accepted on stale numbers is refused there and shown
/// under Sync → Needs attention, with the amount kept.
Failure? paymentBalanceProblem({
  required int signed,
  required int alreadyPaid,
  required int? billed,
  required bool waived,
}) {
  if (signed < 0) {
    if (alreadyPaid + signed < 0) {
      return Failure(
        message: 'Only ${Paise(alreadyPaid < 0 ? 0 : alreadyPaid).display} '
            'was collected.',
        fix: 'A refund cannot give back more than was paid.',
        code: 'refund_exceeds_paid',
      );
    }
    return null;
  }
  if (billed == null || waived) return null;
  final due = billed - alreadyPaid;
  if (signed > due) {
    return Failure(
      message: due <= 0
          ? 'This bill is already paid.'
          : 'Only ${Paise(due).display} is due.',
      fix: due <= 0
          ? 'Nothing more to collect. Refresh if another device took it.'
          : 'Record ${Paise(due).display}; return any change in cash.',
      code: 'overpayment',
    );
  }
  return null;
}

/// A waive writes off what the customer did not pay, so it always says why.
/// The server audits the reason with the amount written off (who, when, how
/// much); the owner sees it in the bill's history on the dashboard.
const waiveReasonRequired = Failure(
  message: 'A waived bill needs a reason.',
  fix: 'Say why it is complimentary, then end it.',
  code: 'waive_reason_required',
);

/// An end set earlier than when staff ended the session lowers the bill, so it
/// always says why; the server audits it with the bill before and after.
const endReasonRequired = Failure(
  message: 'An earlier end needs a reason.',
  fix: 'Say why the session ended earlier, then end it.',
  code: 'end_reason_required',
);

/// Below owner level a waive may write off at most [maxPercent] of the bill —
/// the manual-discount cap — exactly as the server checks it (_waive_check:
/// written off × 100 > billed × cap). Null when allowed.
Failure? waiveOverLimit({
  required bool ownerLevel,
  required int billedPaise,
  required int paidPaise,
  required int maxPercent,
}) {
  if (ownerLevel) return null;
  final writtenOff = billedPaise - paidPaise > 0 ? billedPaise - paidPaise : 0;
  if (writtenOff * 100 <= billedPaise * maxPercent) return null;
  return Failure(
    message: 'Only an owner can waive this much.',
    fix: maxPercent == 0
        ? 'Ask an owner to end it as waived.'
        : 'You may waive up to $maxPercent% of a bill. Take payment for the '
              'rest, or ask an owner.',
    code: 'waive_over_limit',
  );
}

/// Without the settings permission a manual discount may take off at most
/// [maxPercent] of the subtotal, exactly as the server checks it
/// (_discount_apply: amount > _pr_div(subtotal × cap, 100)). Null when allowed.
Failure? discountOverLimit({
  required bool canSettings,
  required int discountPaise,
  required int subtotalPaise,
  required int maxPercent,
}) {
  if (canSettings) return null;
  if (discountPaise <= roundDivHalfUp(subtotalPaise * maxPercent, 100)) return null;
  return Failure(
    message: 'Only an owner can lower the bill this much.',
    fix: maxPercent == 0
        ? 'Ask an owner, or set a manual discount limit in Settings.'
        : 'You may lower a bill by up to $maxPercent%. Ask an owner for more.',
    code: 'discount_over_limit',
  );
}
