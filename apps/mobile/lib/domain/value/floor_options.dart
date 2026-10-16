/// What the floor offers staff, set by the owner on the admin dashboard and synced as the
/// `floor_options` setting: the payment methods shown when taking money, the duration
/// choices when starting a session, and how long before the booked end a station turns amber.
///
/// Not part of pricing: a session's bill never depends on these. The server validates them
/// (`_floor_options`) but still records any known payment method, so a payment taken offline
/// is never refused after the fact.
library;

import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

@immutable
class FloorOptions {
  const FloorOptions({
    required this.paymentMethods,
    required this.startPresets,
    required this.warnMinutes,
  });

  /// The behaviour before the arena sets any: every method, 30–120 min, a 5-minute warning.
  static const defaults = FloorOptions(
    paymentMethods: PaymentMethod.values,
    startPresets: [30, 60, 90, 120],
    warnMinutes: 5,
  );

  /// Methods offered when taking a payment, in the app's usual order. Never empty.
  final List<PaymentMethod> paymentMethods;

  /// Duration choices (minutes) when starting a session or a booking. Never empty.
  final List<int> startPresets;

  /// Minutes before the booked end at which the floor warns staff.
  final int warnMinutes;

  Duration get warnThreshold => Duration(minutes: warnMinutes);

  /// Reads the synced setting tolerantly: unknown method codes (from a newer server) are
  /// skipped, and anything missing or empty falls back to [defaults].
  factory FloorOptions.fromJson(Map<String, dynamic> json) {
    final codes = (json['payment_methods'] as List?)?.whereType<String>().toSet() ?? const {};
    final methods = [
      for (final m in PaymentMethod.values)
        if (codes.contains(m.code)) m,
    ];
    final presets = ((json['start_presets'] as List?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .where((n) => n >= 5 && n <= 720)
        .toSet()
        .toList()
      ..sort();
    final warn = (json['warn_minutes'] as num?)?.toInt();
    return FloorOptions(
      paymentMethods: methods.isEmpty ? defaults.paymentMethods : methods,
      startPresets: presets.isEmpty ? defaults.startPresets : presets,
      warnMinutes: warn != null && warn >= 1 && warn <= 30 ? warn : defaults.warnMinutes,
    );
  }

  /// [picked] when it is offered, otherwise the first method that is.
  PaymentMethod methodOr(PaymentMethod picked) =>
      paymentMethods.contains(picked) ? picked : paymentMethods.first;

  @override
  bool operator ==(Object other) =>
      other is FloorOptions &&
      _listEq(other.paymentMethods, paymentMethods) &&
      _listEq(other.startPresets, startPresets) &&
      other.warnMinutes == warnMinutes;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(paymentMethods), Object.hashAll(startPresets), warnMinutes);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
