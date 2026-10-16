import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';

/// Plays the server for leave: keeps requests in memory and counts every
/// requested day as a working day; [nextFailure] answers the next call.
class FakeLeaveRepository implements LeaveRepository {
  FakeLeaveRepository({required this.now, LeaveBalance? balance})
      : balance = balance ??
            const LeaveBalance(
              joinedOn: IstDate(2025, 6, 1),
              yearStart: IstDate(2026, 6, 1),
              yearEnd: IstDate(2027, 5, 31),
              allowance: 12,
              used: 4,
              balance: 8,
            );

  DateTime Function() now;
  LeaveBalance balance;
  final requests = <LeaveRequest>[];
  final sent = <LeaveRequestCommand>[];
  final cancelled = <String>[];
  Failure? nextFailure;

  Failure? _take() {
    final f = nextFailure;
    nextFailure = null;
    return f;
  }

  @override
  Future<Result<LeaveBalance>> myBalance() async => Ok(balance);

  @override
  Future<Result<List<LeaveRequest>>> myRequests() async =>
      Ok([...requests]..sort((a, b) => b.from.compareTo(a.from)));

  @override
  Future<Result<double>> request(LeaveRequestCommand cmd) async {
    sent.add(cmd);
    final f = _take();
    if (f != null) return Err(f);
    var days = 0.0;
    for (var d = cmd.from; d.compareTo(cmd.to) <= 0; d = d.addDays(1)) {
      days += cmd.halfDay == HalfDay.none ? 1 : 0.5;
    }
    requests.add(LeaveRequest(
      id: cmd.id,
      kind: cmd.kind,
      from: cmd.from,
      to: cmd.to,
      halfDay: cmd.halfDay,
      days: days,
      reason: cmd.reason,
      status: LeaveStatus.pending,
      createdAt: now(),
    ));
    return Ok(days);
  }

  @override
  Future<Result<LeaveStatus>> cancel(String id, {String? reason}) async {
    cancelled.add(id);
    final f = _take();
    if (f != null) return Err(f);
    final i = requests.indexWhere((r) => r.id == id);
    final r = requests[i];
    final status =
        r.status == LeaveStatus.pending ? LeaveStatus.cancelled : LeaveStatus.cancelPending;
    requests[i] = LeaveRequest(
      id: r.id,
      kind: r.kind,
      from: r.from,
      to: r.to,
      halfDay: r.halfDay,
      days: r.days,
      paidDays: r.paidDays,
      lopDays: r.lopDays,
      reason: r.reason,
      status: status,
      createdAt: r.createdAt,
    );
    return Ok(status);
  }
}
