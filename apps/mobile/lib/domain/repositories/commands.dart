/// Command objects for the critical session operations (spec §32). The
/// application layer computes prices with the pure services and hands the
/// repository the facts to persist; the repository re-checks conflicts and
/// writes atomically.
library;

import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

/// Starts a parent session and its first segment (spec §6–§9).
@immutable
class StartSessionCommand {
  const StartSessionCommand({
    required this.customerId,
    required this.startedAt,
    required this.scheduledEndAt,
    required this.snapshot,
    required this.resourceId,
    required this.resourceName,
    required this.activityCode,
    this.gameId,
    this.controllerCount,
    this.controllerIds,
    this.borrowControllerIds,
    this.bookingId,
    this.requestId,
  });

  final String customerId;
  final DateTime startedAt;
  final DateTime scheduledEndAt;
  final PricingSnapshot snapshot;

  // First segment configuration.
  final String resourceId;
  final String resourceName;
  final String activityCode;
  final String? gameId;
  final int? controllerCount;

  /// Specific physical controllers to allocate (brief §3). When null the
  /// session is count-only (today's behaviour); when present each id is
  /// validated and reserved so no pad is double-allocated.
  final List<String>? controllerIds;

  /// Subset of [controllerIds] standing at another station: they are moved
  /// (borrowed) to this station in the same transaction, with a location
  /// history row, before being allocated. Null = none borrowed.
  final List<String>? borrowControllerIds;

  final String? bookingId;
  final String? requestId;
}

/// Closes the current open segment at [at] and opens a new one with the given
/// configuration (spec §10–§13). Used by switch-system, change-game and
/// change-controllers — they differ only in which fields change.
@immutable
class ReconfigureCommand {
  const ReconfigureCommand({
    required this.sessionId,
    required this.at,
    required this.resourceId,
    required this.resourceName,
    required this.activityCode,
    this.gameId,
    this.controllerCount,
    this.controllerIds,
    this.borrowControllerIds,
  });

  final String sessionId;
  final DateTime at;
  final String resourceId;
  final String resourceName;
  final String activityCode;
  final String? gameId;
  final int? controllerCount;

  /// Specific physical controllers for the new segment (brief §3, §8). Null
  /// keeps the count-only behaviour; the mid-session move preserves the parent
  /// timer and the per-pad allocation history either way.
  final List<String>? controllerIds;

  /// Subset of [controllerIds] standing at another station: they are moved
  /// (borrowed) to this station in the same transaction, with a location
  /// history row, before being allocated. Null = none borrowed.
  final List<String>? borrowControllerIds;
}

@immutable
class ExtendSessionCommand {
  const ExtendSessionCommand({
    required this.sessionId,
    required this.addedMinutes,
    required this.newEndAt,
    required this.addedAmountPaise,
    this.reason,
    this.requestId,
  });

  final String sessionId;
  final int addedMinutes;
  final DateTime newEndAt;
  final int addedAmountPaise;
  final String? reason;
  final String? requestId;
}

@immutable
class EndSessionCommand {
  const EndSessionCommand({
    required this.sessionId,
    required this.actualEndedAt,
    required this.charges,
    required this.billedAmountPaise,
    this.markWaived = false,
  });

  final String sessionId;
  final DateTime actualEndedAt;

  /// Immutable final segments (built from all session segments at end).
  final List<SessionCharge> charges;
  final int billedAmountPaise;

  /// Complimentary session: billed amount is forgiven (spec §28).
  final bool markWaived;
}

@immutable
class RecordPaymentCommand {
  const RecordPaymentCommand({
    required this.sessionId,
    required this.amountPaise,
    required this.method,
    this.isRefund = false,
    this.note,
    this.reason,
    this.requestId,
  });

  final String sessionId;
  final int amountPaise;
  final PaymentMethod method;
  final bool isRefund;
  final String? note;
  final String? reason;
  final String? requestId;
}
