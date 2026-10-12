import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'payment.freezed.dart';

/// An append-only payment row (spec §20). A refund is a negative row with a
/// reason. Payments are never overwritten; the session's payment total is the
/// sum of its payment rows.
@freezed
abstract class Payment with _$Payment {
  const Payment._();

  const factory Payment({
    required String id,
    required String sessionId,
    required int amountPaise, // negative = refund
    required PaymentMethod method,
    @Default(false) bool isRefund,
    String? note,
    String? reason,
    required DateTime createdAt,
  }) = _Payment;

  Paise get amount => Paise(amountPaise);
}
