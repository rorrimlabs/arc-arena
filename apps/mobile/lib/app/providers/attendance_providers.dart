/// Riverpod wiring for attendance: the online repository, the location probe
/// and the person's own log.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/device/geolocator_location_probe.dart';
import 'package:arena_ops/data/remote/unavailable_attendance_repository.dart';
import 'package:arena_ops/data/remote/unavailable_attendance_request_repository.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_request.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:arena_ops/domain/repositories/attendance_request_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in cloud mode with the server-backed repository; local-only
/// builds explain that attendance needs the online arena.
final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => const UnavailableAttendanceRepository(),
);

/// Missed-punch requests; overridden in cloud mode like the repository above.
final attendanceRequestRepositoryProvider =
    Provider<AttendanceRequestRepository>(
  (ref) => const UnavailableAttendanceRequestRepository(),
);

/// The signed-in person's own missed-punch requests, newest first.
final myAttendanceRequestsProvider =
    FutureProvider.autoDispose<Result<List<AttendanceRequest>>>(
  (ref) => ref.watch(attendanceRequestRepositoryProvider).myRequests(),
);

final locationProbeProvider = Provider<LocationProbe>(
  (ref) => const GeolocatorLocationProbe(),
);

final locationSettingsOpenerProvider = Provider<LocationSettingsOpener>(
  (ref) => const GeolocatorLocationProbe(),
);

/// Whether this run can clock in at all: only when connected to an arena
/// online (the offline demo has no server to time a punch).
final attendanceAvailableProvider =
    Provider<bool>((ref) => ref.watch(cloudBindingProvider) != null);

/// Map tiles come from the network; widget tests turn them off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// How many days of history the attendance screens show.
const attendanceHistoryDays = 31;

final attendanceRulesProvider =
    FutureProvider.autoDispose<Result<AttendanceRules>>(
  (ref) => ref.watch(attendanceRepositoryProvider).rules(),
);

/// The signed-in person's own entries for the last [attendanceHistoryDays]
/// IST days, newest first.
final myAttendanceProvider =
    FutureProvider.autoDispose<Result<List<AttendanceEntry>>>((ref) {
  final today = IstDate.fromUtc(ref.watch(clockProvider).now());
  return ref.watch(attendanceRepositoryProvider).myEntries(
        from: today.addDays(-(attendanceHistoryDays - 1)),
        to: today,
      );
});

/// The signed-in person's days (status, worked, extra) for the same window as
/// [myAttendanceProvider], oldest first.
final myAttendanceDaysProvider =
    FutureProvider.autoDispose<Result<List<AttendanceDay>>>((ref) {
  final today = IstDate.fromUtc(ref.watch(clockProvider).now());
  return ref.watch(attendanceRepositoryProvider).myDays(
        from: today.addDays(-(attendanceHistoryDays - 1)),
        to: today,
      );
});
