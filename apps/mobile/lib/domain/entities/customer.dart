import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

/// A gaming-center customer (spec §21). Statistics (visits, spend, favourite
/// activity …) are NOT stored here — they are derived from session/payment
/// facts by the reporting layer.
@freezed
abstract class Customer with _$Customer {
  const Customer._();

  const factory Customer({
    required String id,
    required String name,
    String? phone,
    String? notes,
    DateTime? lastVisitAt,
    /// A walk-in started without registering. One record per visit, so the
    /// visit is still counted and billed, but the Members directory is not
    /// filled with anonymous rows.
    @Default(false) bool isGuest,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Customer;

  /// What to show on a card for this person.
  String get displayName => isGuest ? 'Walk-in' : name;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}
