import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';

/// Persistence for group sessions (group feature §1–§9). Writes re-check
/// conflicts across both single sessions and group assignments and commit
/// atomically; reads are Drift streams so the floor updates live.
abstract interface class GroupSessionRepository {
  /// Active groups, each with all their assignments (open and closed).
  Stream<List<ActiveGroupSession>> watchActiveGroups();
  Future<List<ActiveGroupSession>> activeGroups();

  /// Currently open assignments across all groups — a source of resource
  /// occupancy alongside single-session open segments (group feature §7).
  Stream<List<GroupAssignment>> watchOpenAssignments();
  Future<List<GroupAssignment>> openAssignments();

  Future<GroupSession?> getById(String id);
  Stream<GroupSession?> watchById(String id);
  Future<List<GroupAssignment>> assignmentsFor(String groupId);

  Future<List<GroupSession>> recent({int limit});
  Future<List<GroupSession>> inRange(DateTime fromUtc, DateTime toUtc);

  /// Assignments, charge rows and payments overlapping the window — the group
  /// half of the owner reports (brief §13).
  Future<List<GroupAssignment>> assignmentsInRange(
      DateTime fromUtc, DateTime toUtc);
  Future<List<GroupCharge>> chargesInRange(DateTime fromUtc, DateTime toUtc);
  Future<List<GroupPayment>> paymentsInRange(DateTime fromUtc, DateTime toUtc);

  // Critical operations.
  Future<Result<GroupSession>> create(CreateGroupCommand cmd);
  Future<Result<GroupAssignment>> addAssignment(AddAssignmentCommand cmd);

  /// Switch system / change game / change controllers for one player.
  Future<Result<GroupAssignment>> switchAssignment(SwitchAssignmentCommand cmd);
  Future<Result<void>> endAssignment(EndAssignmentCommand cmd);

  Future<Result<GroupSession>> extend(ExtendGroupCommand cmd);
  Future<Result<GroupSession>> end(EndGroupCommand cmd);
  Future<Result<GroupSession>> voidGroup(String id, String reason);

  // History reads.
  Future<List<GroupExtension>> extensionsFor(String groupId);
  Future<List<GroupCharge>> chargesFor(String groupId);

  // Payments.
  Future<List<GroupPayment>> paymentsFor(String groupId);
  Stream<List<GroupPayment>> watchPaymentsFor(String groupId);
  Future<Result<GroupPayment>> recordPayment(RecordGroupPaymentCommand cmd);
}
