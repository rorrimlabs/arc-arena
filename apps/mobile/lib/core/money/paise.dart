/// Money in arena_ops is **always** integer paise (1 rupee = 100 paise).
///
/// Never use `double` for money. All pricing arithmetic happens in paise and
/// only the final display converts to a human string.
library;

import 'package:meta/meta.dart';

/// An immutable money amount stored as whole paise.
@immutable
class Paise implements Comparable<Paise> {
  const Paise(this.value);

  /// Construct from whole rupees (e.g. `Paise.rupees(150)` == ₹150.00).
  const Paise.rupees(int rupees) : value = rupees * 100;

  static const Paise zero = Paise(0);

  /// The amount in paise. Can be negative (e.g. a refund row, or change due).
  final int value;

  bool get isZero => value == 0;
  bool get isNegative => value < 0;
  bool get isPositive => value > 0;

  Paise operator +(Paise other) => Paise(value + other.value);
  Paise operator -(Paise other) => Paise(value - other.value);
  Paise operator *(int factor) => Paise(value * factor);
  Paise operator -() => Paise(-value);

  @override
  int compareTo(Paise other) => value.compareTo(other.value);

  bool operator <(Paise other) => value < other.value;
  bool operator <=(Paise other) => value <= other.value;
  bool operator >(Paise other) => value > other.value;
  bool operator >=(Paise other) => value >= other.value;

  /// `₹1,234` when whole, `₹1,234.50` when there are paise.
  /// Thousands grouped in the Indian style (lakh/crore) is overkill for a
  /// counter display, so we group in plain thousands.
  String get display {
    final negative = value < 0;
    final abs = value.abs();
    final rupees = abs ~/ 100;
    final paise = abs % 100;
    final grouped = _group(rupees);
    final body = paise == 0
        ? '₹$grouped'
        : '₹$grouped.${paise.toString().padLeft(2, '0')}';
    return negative ? '-$body' : body;
  }

  static String _group(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    final firstGroup = s.length % 3 == 0 ? 3 : s.length % 3;
    buf.write(s.substring(0, firstGroup));
    for (var i = firstGroup; i < s.length; i += 3) {
      buf.write(',');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  @override
  bool operator ==(Object other) => other is Paise && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Paise($value)';
}
