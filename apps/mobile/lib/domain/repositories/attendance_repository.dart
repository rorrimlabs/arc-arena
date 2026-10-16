/// Clock-in / clock-out and the person's own attendance log.
///
/// Online only: the server stamps every punch with its own time, so there is
/// no offline queue — a punch that cannot reach the server is refused, never
/// stored for later.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:meta/meta.dart';

/// One punch to send. [punchId] is also the sync op id, so sending the same
/// command again (after a dropped connection) can never record it twice.
@immutable
class PunchCommand {
  const PunchCommand({
    required this.punchId,
    required this.kind,
    required this.reading,
    required this.deviceAt,
  });

  final String punchId;
  final PunchKind kind;
  final LocationReading reading;

  /// The phone's own clock at the tap (evidence only; the server's time counts).
  final DateTime deviceAt;
}

/// What the server recorded.
@immutable
class PunchOutcome {
  const PunchOutcome({
    required this.punchId,
    required this.entryId,
    required this.kind,
    required this.serverAt,
    required this.verdict,
    this.distanceM,
    this.flags = const [],
    this.review = 'none',
    this.autoClosedEntryId,
  });

  final String punchId;
  final String entryId;
  final PunchKind kind;
  final DateTime serverAt;
  final GeofenceVerdict verdict;
  final int? distanceM;
  final List<String> flags;
  final String review;

  /// A clock-in left open too long that this punch closed automatically.
  final String? autoClosedEntryId;

  bool get needsReview => review == 'pending';
}

abstract interface class AttendanceRepository {
  /// The arena's rules (defaults when the owner has set none).
  Future<Result<AttendanceRules>> rules();

  /// The signed-in person's own entries with work dates in [from]..[to],
  /// newest first.
  Future<Result<List<AttendanceEntry>>> myEntries({
    required IstDate from,
    required IstDate to,
  });

  Future<Result<PunchOutcome>> punch(PunchCommand cmd);

  /// The signed-in person's days in [from]..[to] as the server judges them
  /// (status, worked and extra minutes), oldest first.
  Future<Result<List<AttendanceDay>>> myDays({
    required IstDate from,
    required IstDate to,
  });
}
