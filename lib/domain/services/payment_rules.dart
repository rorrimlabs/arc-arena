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
