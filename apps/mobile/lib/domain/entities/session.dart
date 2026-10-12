import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';

/// The parent, continuous paid session (spec §9). A customer may switch system,
/// game or controller count during one session; those live in [SessionSegment]s,
/// NOT on the parent. The parent owns the customer, the overall time window, the
/// immutable pricing snapshot (spec §31) and payment.
@freezed
abstract class Session with _$Session {
  const Session._();

  const factory Session({
    required String id,
    String? bookingId,
    required String customerId,
    required SessionStatus status,
    required PaymentStatus paymentStatus,
    required DateTime startedAt,
    required DateTime scheduledEndAt,
    DateTime? actualEndedAt,
    required Map<String, dynamic> pricingSnapshot,
    int? billedAmountPaise,
    String? voidReason,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Session;

  bool get isActive => status == SessionStatus.active;

  PricingSnapshot get snapshot => PricingSnapshot.fromJson(pricingSnapshot);

  Paise? get billedAmount =>
      billedAmountPaise == null ? null : Paise(billedAmountPaise!);
}

/// One stretch of a parent session with a fixed configuration (spec §9–§14).
/// [endedAt] is null for the current, open segment. Segments never overlap and
/// leave no gaps: a switch closes one and opens the next at the same instant.
@freezed
abstract class SessionSegment with _$SessionSegment {
  const SessionSegment._();

  const factory SessionSegment({
    required String id,
    required String sessionId,
    required int index,
    required String resourceId,
    required String activityCode,
    String? gameId,
    int? controllerCount,
    required DateTime startedAt,
    DateTime? endedAt,
    required DateTime createdAt,
  }) = _SessionSegment;

  bool get isOpen => endedAt == null;

  /// Duration up to [now] for an open segment, or its fixed span if closed.
  Duration playedUpTo(DateTime now) => (endedAt ?? now).difference(startedAt);
}

/// A parent session together with its ordered segments — what the floor needs
/// to show the current configuration and compute the live amount.
@freezed
abstract class ActiveSession with _$ActiveSession {
  const ActiveSession._();

  const factory ActiveSession({
    required Session session,
    required List<SessionSegment> segments,
  }) = _ActiveSession;

  /// The open segment (there is always exactly one while active).
  SessionSegment get current =>
      segments.firstWhere((s) => s.isOpen, orElse: () => segments.last);
}

/// Append-only extension history (spec §13). Never overwritten.
@freezed
abstract class SessionExtension with _$SessionExtension {
  const factory SessionExtension({
    required String id,
    required String sessionId,
    required int addedMinutes,
    required DateTime oldEndAt,
    required DateTime newEndAt,
    @Default(0) int addedAmountPaise,
    String? reason,
    required DateTime createdAt,
  }) = _SessionExtension;
}

/// Immutable final pricing segment written at end (spec §14, §31). Tied to the
/// [SessionSegment] it was priced from (a segment can yield several charges when
/// it spans a happy-hour boundary).
@freezed
abstract class SessionCharge with _$SessionCharge {
  const factory SessionCharge({
    required String id,
    required String sessionId,
    String? segmentId,
    required int segmentIndex,
    required String bandCode,
    required String activityCode,
    String? resourceId,
    int? controllerCount,
    required DateTime segmentStart,
    required DateTime segmentEnd,
    required int playedMinutes,
    required int billedMinutes,
    required int unitMinutes,
    required int unitPricePaise,
    required int amountPaise,
  }) = _SessionCharge;
}
