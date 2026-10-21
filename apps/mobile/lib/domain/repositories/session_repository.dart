import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/entities/payment.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/repositories/commands.dart';

abstract interface class SessionRepository {
  /// Active parent sessions, each with its ordered segments (spec §9, §16).
  Stream<List<ActiveSession>> watchActive();
  Future<List<ActiveSession>> active();

  /// Currently open segments (one per busy resource) — the source of truth for
  /// resource occupancy (spec §1, §24).
  Stream<List<SessionSegment>> watchOpenSegments();
  Future<List<SessionSegment>> openSegments();

  Future<Session?> getById(String id);
  Stream<Session?> watchById(String id);
  Future<List<SessionSegment>> segmentsFor(String sessionId);
  Stream<List<SessionSegment>> watchSegmentsFor(String sessionId);

  /// Completed sessions whose money is not settled yet (unpaid / partial) —
  /// the floor's "awaiting payment" queue (brief §3, §10).
  Stream<List<Session>> watchAwaitingPayment();

  Future<List<Session>> recent({int limit});
  Future<List<Session>> forCustomer(String customerId);
  Future<List<Session>> inRange(DateTime fromUtc, DateTime toUtc);

  /// Every segment overlapping [fromUtc, toUtc) — the basis for utilisation
  /// and most-played-game reports (brief §13).
  Future<List<SessionSegment>> segmentsInRange(DateTime fromUtc, DateTime toUtc);

  /// Immutable charge rows for sessions that ended in the window — the basis
  /// for revenue by activity and by price band.
  Future<List<SessionCharge>> chargesInRange(DateTime fromUtc, DateTime toUtc);

  // Critical operations (re-check conflicts + write atomically).
  Future<Result<Session>> start(StartSessionCommand cmd);

  /// Switch system / change game / change controllers: closes the open segment
  /// at cmd.at and opens a new one (spec §10–§13). No lost or overlapping time.
  Future<Result<SessionSegment>> reconfigure(ReconfigureCommand cmd);

  Future<Result<Session>> extend(ExtendSessionCommand cmd);
  Future<Result<Session>> end(EndSessionCommand cmd);
  Future<Result<Session>> voidSession(String id, String reason);

  // History reads.
  Future<List<SessionExtension>> extensionsFor(String sessionId);
  Future<List<SessionCharge>> chargesFor(String sessionId);

  // Payments (append-only).
  Future<List<Payment>> paymentsFor(String sessionId);
  Stream<List<Payment>> watchPaymentsFor(String sessionId);
  Future<Result<Payment>> recordPayment(RecordPaymentCommand cmd);
  Future<List<Payment>> paymentsInRange(DateTime fromUtc, DateTime toUtc);
}
