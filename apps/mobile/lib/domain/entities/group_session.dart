import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'group_session.freezed.dart';

/// The parent of a group session: one primary customer books several players and
/// controllers for ONE continuous, shared time window (group feature §1, §3).
///
/// Mirrors [Session], but a group may occupy several systems at once. Per-player,
/// per-system configuration lives in [GroupAssignment]s, NOT here. The parent owns
/// the primary customer, player/controller counts, the single authoritative
/// `startedAt`/`scheduledEndAt` that every assignment's countdown reads, the
/// immutable pricing snapshot, the billing mode and the payment rollup.
@freezed
abstract class GroupSession with _$GroupSession {
  const GroupSession._();

  const factory GroupSession({
    required String id,
    required String primaryCustomerId,
    required int playerCount,
    required int purchasedControllerCount,
    required GroupSessionStatus status,
    required PaymentStatus paymentStatus,
    required DateTime startedAt,
    required DateTime scheduledEndAt,
    DateTime? actualEndedAt,
    required Map<String, dynamic> pricingSnapshot,
    required GroupBillingMode billingMode,
    int? billedAmountPaise,
    String? voidReason,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _GroupSession;

  bool get isActive => status == GroupSessionStatus.active;

  PricingSnapshot get snapshot => PricingSnapshot.fromJson(pricingSnapshot);

  Paise? get billedAmount =>
      billedAmountPaise == null ? null : Paise(billedAmountPaise!);
}

/// One player's use of one (resource, game, controllers) for a stretch of the
/// group's window (group feature §4). The group analog of a session segment, but
/// MANY assignments can be open at once (one per player). `endedAt` is null for a
/// player's current, open assignment. A switch closes one and opens the next at
/// the same instant, so a player's assignments tile their time with no gaps or
/// overlaps. Assignments inherit the parent's end time — they carry no end of
/// their own, which is what keeps the countdown shared and switch-proof.
@freezed
abstract class GroupAssignment with _$GroupAssignment {
  const GroupAssignment._();

  const factory GroupAssignment({
    required String id,
    required String groupId,
    required int playerNumber,
    String? playerLabel,
    required int index,
    required String resourceId,
    required String activityCode,
    String? gameId,
    int? controllerCount,
    required DateTime startedAt,
    DateTime? endedAt,
    required DateTime createdAt,
  }) = _GroupAssignment;

  bool get isOpen => endedAt == null;

  /// Duration up to [now] for an open assignment, or its fixed span if closed.
  Duration playedUpTo(DateTime now) => (endedAt ?? now).difference(startedAt);
}

/// A parent group together with its assignments — what the floor and detail
/// screens need to show every player's current system and the shared countdown.
@freezed
abstract class ActiveGroupSession with _$ActiveGroupSession {
  const ActiveGroupSession._();

  const factory ActiveGroupSession({
    required GroupSession group,
    required List<GroupAssignment> assignments,
  }) = _ActiveGroupSession;

  /// The currently open assignments (one per active player), across all systems.
  List<GroupAssignment> get openAssignments =>
      [for (final a in assignments) if (a.isOpen) a];

  /// Resources this group is occupying right now (deduplicated).
  Set<String> get occupiedResourceIds =>
      {for (final a in openAssignments) a.resourceId};

  /// Distinct player numbers, ascending.
  List<int> get playerNumbers =>
      (assignments.map((a) => a.playerNumber).toSet().toList())..sort();

  List<GroupAssignment> assignmentsForPlayer(int playerNumber) => [
        for (final a in assignments)
          if (a.playerNumber == playerNumber) a,
      ]..sort((x, y) => x.index.compareTo(y.index));

  /// The open assignment for [playerNumber], or null if that player has none.
  GroupAssignment? currentForPlayer(int playerNumber) {
    for (final a in assignments) {
      if (a.playerNumber == playerNumber && a.isOpen) return a;
    }
    return null;
  }
}

/// Append-only group-extension history (group feature §8). Never overwritten.
@freezed
abstract class GroupExtension with _$GroupExtension {
  const factory GroupExtension({
    required String id,
    required String groupId,
    required int addedMinutes,
    required DateTime oldEndAt,
    required DateTime newEndAt,
    @Default(0) int addedAmountPaise,
    String? reason,
    required DateTime createdAt,
  }) = _GroupExtension;
}

/// A group payment (append-only; a refund is a row with [isRefund] true). Kept
/// separate from single-session [Payment]s.
@freezed
abstract class GroupPayment with _$GroupPayment {
  const factory GroupPayment({
    required String id,
    required String groupId,
    required int amountPaise,
    required PaymentMethod method,
    @Default(false) bool isRefund,
    String? note,
    String? reason,
    required DateTime createdAt,
  }) = _GroupPayment;
}

/// Immutable final pricing line for a group (group feature §9), written at end.
/// A line may aggregate several co-located players on one system (per-system
/// mode) or be a synthetic pooled line (shared-controller-pool mode), so
/// [assignmentId] and [playerNumber] are optional.
@freezed
abstract class GroupCharge with _$GroupCharge {
  const factory GroupCharge({
    required String id,
    required String groupId,
    String? assignmentId,
    int? playerNumber,
    required int chargeIndex,
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
  }) = _GroupCharge;
}
