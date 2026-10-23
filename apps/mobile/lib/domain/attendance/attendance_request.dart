/// A request to fix your own attendance after a missed punch
/// (attendance_requests): it counts only once a reviewer approves it.
library;

enum AttendanceRequestKind {
  /// A stretch that was never punched: clock-in and clock-out.
  add('add', 'Missed clock-in and out'),

  /// The clock-out of an entry that was never closed, or closed automatically.
  fixOut('fix_out', 'Fix a clock-out');

  const AttendanceRequestKind(this.wire, this.label);
  final String wire;
  final String label;

  static AttendanceRequestKind fromWire(String? w) =>
      w == 'fix_out' ? fixOut : add;
}

enum AttendanceRequestStatus {
  pending,
  approved,
  rejected;

  static AttendanceRequestStatus fromWire(String? w) => switch (w) {
    'approved' => approved,
    'rejected' => rejected,
    _ => pending,
  };
}

class AttendanceRequest {
  const AttendanceRequest({
    required this.id,
    required this.kind,
    required this.inAt,
    required this.outAt,
    required this.reason,
    required this.status,
    this.decisionNote,
    required this.createdAt,
  });

  factory AttendanceRequest.fromJson(Map<String, dynamic> j) =>
      AttendanceRequest(
        id: j['id'] as String,
        kind: AttendanceRequestKind.fromWire(j['kind'] as String?),
        inAt: DateTime.parse(j['in_at'] as String).toUtc(),
        outAt: DateTime.parse(j['out_at'] as String).toUtc(),
        reason: j['reason'] as String? ?? '',
        status: AttendanceRequestStatus.fromWire(j['status'] as String?),
        decisionNote: j['decision_note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
      );

  final String id;
  final AttendanceRequestKind kind;
  final DateTime inAt;
  final DateTime outAt;
  final String reason;
  final AttendanceRequestStatus status;
  final String? decisionNote;
  final DateTime createdAt;
}

/// Sync op `attendance.request`; [id] is the row id and the op id.
class AttendanceRequestCommand {
  const AttendanceRequestCommand({
    required this.id,
    required this.kind,
    this.entryId,
    this.inAt,
    required this.outAt,
    required this.reason,
  });

  final String id;
  final AttendanceRequestKind kind;

  /// The entry whose clock-out is fixed ([AttendanceRequestKind.fixOut]).
  final String? entryId;

  /// The clock-in of a missed stretch ([AttendanceRequestKind.add]).
  final DateTime? inAt;
  final DateTime outAt;
  final String reason;

  Map<String, dynamic> toPayload() => {
    'id': id,
    'kind': kind.wire,
    if (entryId != null) 'entry_id': entryId,
    if (inAt != null) 'in_at': inAt!.toUtc().toIso8601String(),
    'out_at': outAt.toUtc().toIso8601String(),
    'reason': reason.trim(),
  };
}
