/// Deterministic integer rounding helpers for money math. No floating point.
///
/// SERVER PARITY: the server re-prices every bill with a plpgsql port of this
/// code (migration 0013, `_pr_*`) and refuses any difference. Changing how
/// money is computed here needs a matching new migration and a green
/// Dart-vs-SQL parity check — see docs/SYNC.md "Changing pricing".
library;

import 'package:arena_ops/domain/value/enums.dart';

/// Rounds `numerator / denominator` to the nearest whole number, ties going up.
/// Both inputs are non-negative; [denominator] must be > 0.
int roundDivHalfUp(int numerator, int denominator) {
  assert(denominator > 0, 'denominator must be positive');
  assert(numerator >= 0, 'numerator must be non-negative');
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// Smallest multiple of [step] that is >= [value].
int ceilToStep(int value, int step) {
  if (step <= 1) return value;
  return ((value + step - 1) ~/ step) * step;
}

/// Nearest multiple of [step] to [value], ties going up.
int roundToStep(int value, int step) {
  if (step <= 1) return value;
  return ((value + step ~/ 2) ~/ step) * step;
}

/// Applies the configured cash rounding to a paise [value].
int applyMoneyRounding(int value, int stepPaise, MoneyRoundingDir dir) {
  if (stepPaise <= 1) return value;
  return switch (dir) {
    MoneyRoundingDir.up => ceilToStep(value, stepPaise),
    MoneyRoundingDir.nearest => roundToStep(value, stepPaise),
  };
}
