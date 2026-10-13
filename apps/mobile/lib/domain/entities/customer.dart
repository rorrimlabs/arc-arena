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
    /// Year of birth given at registration (for age-rated games); null when not given.
    int? birthYear,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Customer;

  /// What to show on a card for this person.
  String get displayName => isGuest ? 'Walk-in' : name;

  /// Age reached in [year] (from the birth year alone, so it may be one too high before the
  /// birthday); null when no birth year was given.
  int? ageIn(int year) => birthYear == null ? null : year - birthYear!;

  /// Why [text] is not a usable birth year in [currentYear], or null when it is fine (empty
  /// means "not given"). The server applies the same rule (invalid_birth_year).
  static String? birthYearError(String text, int currentYear) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final y = int.tryParse(t);
    if (y == null || y < 1900 || y > currentYear) return 'Enter a year from 1900 to $currentYear';
    return null;
  }

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}
