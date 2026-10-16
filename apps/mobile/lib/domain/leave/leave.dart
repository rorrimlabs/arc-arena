/// Leave as the staff member sees it: their requests and their paid-leave
/// balance (OWNER_CONFIRMATION S5: one allowance per leave year from the
/// joining date; the approver decides how many days are paid and how many are
/// loss of pay). Pay amounts never appear here.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:meta/meta.dart';

enum LeaveKind {
  planned('planned', 'Planned'),
  unplanned('unplanned', 'Unplanned');

  const LeaveKind(this.wire, this.label);
  final String wire;
  final String label;
}

enum HalfDay {
  none('none', 'Full day'),
  firstHalf('first_half', 'First half'),
  secondHalf('second_half', 'Second half');

  const HalfDay(this.wire, this.label);
  final String wire;
  final String label;

  static HalfDay fromWire(String? w) =>
      values.firstWhere((h) => h.wire == w, orElse: () => none);
}

enum LeaveStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  cancelled('cancelled'),
  cancelPending('cancel_pending');

  const LeaveStatus(this.wire);
  final String wire;

  static LeaveStatus fromWire(String? w) =>
      values.firstWhere((s) => s.wire == w, orElse: () => pending);
}

@immutable
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.kind,
    required this.from,
    required this.to,
    this.halfDay = HalfDay.none,
    required this.days,
    this.paidDays,
    this.lopDays,
    required this.reason,
    required this.status,
    this.decisionNote,
    this.decidedAt,
    required this.createdAt,
  });

  final String id;
  final LeaveKind kind;
  final IstDate from;
  final IstDate to;
  final HalfDay halfDay;

  /// Working days the request covers (0.5 for a half day).
  final double days;

  /// Set once approved: how many of [days] are paid, and how many are LOP.
  final double? paidDays;
  final double? lopDays;
  final String reason;
  final LeaveStatus status;
  final String? decisionNote;
  final DateTime? decidedAt;
  final DateTime createdAt;

  /// Can the requester withdraw it (pending), or ask to (approved)?
  bool get cancellable =>
      status == LeaveStatus.pending || status == LeaveStatus.approved;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: j['id'] as String,
        kind: j['kind'] == 'unplanned' ? LeaveKind.unplanned : LeaveKind.planned,
        from: IstDate.parse(j['from_date'] as String),
        to: IstDate.parse(j['to_date'] as String),
        halfDay: HalfDay.fromWire(j['half_day'] as String?),
        days: (j['days'] as num).toDouble(),
        paidDays: (j['paid_days'] as num?)?.toDouble(),
        lopDays: (j['lop_days'] as num?)?.toDouble(),
        reason: j['reason'] as String? ?? '',
        status: LeaveStatus.fromWire(j['status'] as String?),
        decisionNote: j['decision_note'] as String?,
        decidedAt: j['decided_at'] == null
            ? null
            : DateTime.parse(j['decided_at'] as String).toUtc(),
        createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
      );
}

/// The paid-leave balance of the current leave year.
@immutable
class LeaveBalance {
  const LeaveBalance({
    required this.joinedOn,
    required this.yearStart,
    required this.yearEnd,
    required this.allowance,
    this.adjustments = 0,
    this.used = 0,
    this.pending = 0,
    required this.balance,
  });

  final IstDate joinedOn;
  final IstDate yearStart;
  final IstDate yearEnd;
  final double allowance;
  final double adjustments;
  final double used;
  final double pending;
  final double balance;

  /// What is left once pending requests are decided as paid.
  double get available => balance - pending;

  factory LeaveBalance.fromJson(Map<String, dynamic> j) => LeaveBalance(
        joinedOn: IstDate.parse(j['joined_on'] as String),
        yearStart: IstDate.parse(j['year_start'] as String),
        yearEnd: IstDate.parse(j['year_end'] as String),
        allowance: (j['allowance'] as num).toDouble(),
        adjustments: (j['adjustments'] as num?)?.toDouble() ?? 0,
        used: (j['used'] as num?)?.toDouble() ?? 0,
        pending: (j['pending'] as num?)?.toDouble() ?? 0,
        balance: (j['balance'] as num).toDouble(),
      );
}

/// A new request to send. [id] is also the op id: sending it again after a
/// dropped connection cannot create a second request.
@immutable
class LeaveRequestCommand {
  const LeaveRequestCommand({
    required this.id,
    required this.kind,
    required this.from,
    required this.to,
    this.halfDay = HalfDay.none,
    required this.reason,
  });

  final String id;
  final LeaveKind kind;
  final IstDate from;
  final IstDate to;
  final HalfDay halfDay;
  final String reason;

  Map<String, dynamic> toPayload() => {
        'id': id,
        'kind': kind.wire,
        'from_date': from.iso,
        'to_date': to.iso,
        'half_day': halfDay.wire,
        'reason': reason.trim(),
      };
}
