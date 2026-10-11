/// Command objects for the group-session operations (group feature §1–§9). The
/// application layer prices and plans with the pure services and hands the
/// repository the facts to persist; the repository re-checks conflicts across
/// BOTH single sessions and group assignments, then writes atomically.
library;

import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:meta/meta.dart';

/// One player's assignment to a system at group start or when a player is added.
@immutable
class GroupAssignmentDraft {
  const GroupAssignmentDraft({
    required this.playerNumber,
    this.playerLabel,
    required this.resourceId,
    required this.resourceName,
    required this.activityCode,
    this.gameId,
    this.controllerCount,
    this.controllerIds,
    this.borrowControllerIds,
  });

  final int playerNumber;
  final String? playerLabel;
  final String resourceId;
  final String resourceName;
  final String activityCode;
  final String? gameId;
  final int? controllerCount;

  /// Specific physical controllers for this player (brief §3). Null = count-only.
  final List<String>? controllerIds;

  /// Subset of [controllerIds] standing at another station: they are moved
  /// (borrowed) to this station in the same transaction, with a location
  /// history row, before being allocated. Null = none borrowed.
  final List<String>? borrowControllerIds;
}

/// Creates a parent group and its initial player assignments (group feature §1).
@immutable
class CreateGroupCommand {
  const CreateGroupCommand({
    required this.primaryCustomerId,
    required this.playerCount,
    required this.purchasedControllerCount,
    required this.startedAt,
    required this.scheduledEndAt,
    required this.snapshot,
    required this.billingMode,
    required this.assignments,
    this.requestId,
  });

  final String primaryCustomerId;
  final int playerCount;
  final int purchasedControllerCount;
  final DateTime startedAt;
  final DateTime scheduledEndAt;
  final PricingSnapshot snapshot;
  final GroupBillingMode billingMode;
  final List<GroupAssignmentDraft> assignments;
  final String? requestId;
}

/// Opens a new assignment for a player who currently has none (group feature §4).
@immutable
class AddAssignmentCommand {
  const AddAssignmentCommand({
    required this.groupId,
    required this.at,
    required this.playerNumber,
    this.playerLabel,
    required this.resourceId,
    required this.resourceName,
    required this.activityCode,
    this.gameId,
    this.controllerCount,
    this.controllerIds,
    this.borrowControllerIds,
  });

  final String groupId;
  final DateTime at;
  final int playerNumber;
  final String? playerLabel;
  final String resourceId;
  final String resourceName;
  final String activityCode;
  final String? gameId;
  final int? controllerCount;

  /// Specific physical controllers for this player (brief §3). Null = count-only.
  final List<String>? controllerIds;

  /// Subset of [controllerIds] standing at another station: they are moved
  /// (borrowed) to this station in the same transaction, with a location
  /// history row, before being allocated. Null = none borrowed.
  final List<String>? borrowControllerIds;
}

/// Switch system / change game / change controllers for ONE player (group
/// feature §5–§6): closes that player's open assignment at [at] and opens a new
/// one at the same instant. Never touches the parent's time window.
@immutable
class SwitchAssignmentCommand {
  const SwitchAssignmentCommand({
    required this.groupId,
    required this.playerNumber,
    required this.at,
    required this.resourceId,
    required this.resourceName,
    required this.activityCode,
    this.gameId,
    this.controllerCount,
    this.controllerIds,
    this.borrowControllerIds,
  });

  final String groupId;
  final int playerNumber;
  final DateTime at;
  final String resourceId;
  final String resourceName;
  final String activityCode;
  final String? gameId;
  final int? controllerCount;

  /// Specific physical controllers for this player's new assignment (brief §3).
  final List<String>? controllerIds;

  /// Subset of [controllerIds] standing at another station: they are moved
  /// (borrowed) to this station in the same transaction, with a location
  /// history row, before being allocated. Null = none borrowed.
  final List<String>? borrowControllerIds;
}

/// Ends a single player's current assignment (frees their system) without ending
/// the group (group feature §5, §7).
@immutable
class EndAssignmentCommand {
  const EndAssignmentCommand({
    required this.groupId,
    required this.playerNumber,
    required this.at,
  });

  final String groupId;
  final int playerNumber;
  final DateTime at;
}

/// Extends the whole group's shared window (group feature §8).
@immutable
class ExtendGroupCommand {
  const ExtendGroupCommand({
    required this.groupId,
    required this.addedMinutes,
    required this.newEndAt,
    required this.addedAmountPaise,
    this.reason,
    this.requestId,
  });

  final String groupId;
  final int addedMinutes;
  final DateTime newEndAt;
  final int addedAmountPaise;
  final String? reason;
  final String? requestId;
}

/// Ends the group: closes every open assignment at [actualEndedAt], writes the
/// immutable charges and the final billed amount (group feature §9).
@immutable
class EndGroupCommand {
  const EndGroupCommand({
    required this.groupId,
    required this.actualEndedAt,
    required this.charges,
    required this.billedAmountPaise,
    this.markWaived = false,
  });

  final String groupId;
  final DateTime actualEndedAt;
  final List<GroupCharge> charges;
  final int billedAmountPaise;
  final bool markWaived;
}

@immutable
class RecordGroupPaymentCommand {
  const RecordGroupPaymentCommand({
    required this.groupId,
    required this.amountPaise,
    required this.method,
    this.isRefund = false,
    this.note,
    this.reason,
    this.requestId,
  });

  final String groupId;
  final int amountPaise;
  final PaymentMethod method;
  final bool isRefund;
  final String? note;
  final String? reason;
  final String? requestId;
}
