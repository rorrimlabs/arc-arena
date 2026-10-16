/// Attendance in local-only mode (the offline demo, tests without a server):
/// every call explains that clocking in needs the online arena. Punches are
/// timed by the server, so there is nothing a device-only build could record.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';

class UnavailableAttendanceRepository implements AttendanceRepository {
  const UnavailableAttendanceRepository();

  @override
  Future<Result<AttendanceRules>> rules() async =>
      const Err(AttendanceFailures.cloudOnly);

  @override
  Future<Result<List<AttendanceEntry>>> myEntries({
    required IstDate from,
    required IstDate to,
  }) async =>
      const Err(AttendanceFailures.cloudOnly);

  @override
  Future<Result<PunchOutcome>> punch(PunchCommand cmd) async =>
      const Err(AttendanceFailures.cloudOnly);

  @override
  Future<Result<List<AttendanceDay>>> myDays({
    required IstDate from,
    required IstDate to,
  }) async =>
      const Err(AttendanceFailures.cloudOnly);
}
