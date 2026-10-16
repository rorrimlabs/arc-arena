import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';
import 'package:arena_ops/data/remote/unavailable_attendance_repository.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:arena_ops/domain/repositories/attendance_repository.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_history_screen.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_screen.dart';
import 'package:arena_ops/features/attendance/presentation/widgets/attendance_chip.dart';
import 'package:arena_ops/features/attendance/presentation/widgets/punch_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance.dart';
import '../../support/pricing_fixtures.dart' show ist;
import '../../support/test_db.dart' show TestStaffAuth;

void main() {
  // Thursday 15 Oct 2026, 11:00 AM IST.
  final now = ist(2026, 10, 15, 11, 0);
  late FakeClock clock;
  late FakeAttendanceRepository repo;
  late FakeLocationProbe probe;

  setUp(() {
    clock = FakeClock(now);
    repo = FakeAttendanceRepository(serverNow: () => clock.now());
    probe = FakeLocationProbe();
  });

  Widget app(Widget home, {AttendanceRepository? repository, bool online = true}) =>
      ProviderScope(
        overrides: [
          attendanceAvailableProvider.overrideWithValue(online),
          authControllerProvider.overrideWith(TestStaffAuth.new),
          clockProvider.overrideWithValue(clock),
          attendanceRepositoryProvider.overrideWithValue(repository ?? repo),
          locationProbeProvider.overrideWithValue(probe),
          locationSettingsOpenerProvider.overrideWithValue(probe),
          mapTilesEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // The live timer ticks every second: unmount so no timer outlives the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532); // 390 x 844
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(2560, 1600); // 1280 x 800
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$name: clock in, then clock out', (tester) async {
      size(tester);
      await tester.pumpWidget(app(const AttendanceScreen()));
      await settle(tester);
      expect(find.text('CLOCKED OUT'), findsOneWidget);
      expect(find.text('No clock-ins today yet.'), findsOneWidget);

      await tester.tap(find.text('Clock in'));
      await settle(tester);
      expect(repo.sent.single.kind, PunchKind.clockIn);
      expect(find.textContaining('Clocked in at 11:00 AM · inside the arena.'),
          findsOneWidget);
      expect(find.text('ON THE CLOCK'), findsOneWidget);
      expect(find.text('Since 11:00 AM'), findsOneWidget);
      expect(find.text('Inside · 11 m away · ±8 m'), findsOneWidget);
      expect(find.text('11:00 AM → now'), findsOneWidget);

      clock.advance(const Duration(hours: 2, minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2:05:00'), findsOneWidget, reason: 'timer from the stored in time');

      await tester.tap(find.text('Clock out'));
      await settle(tester);
      expect(repo.sent.last.kind, PunchKind.clockOut);
      expect(find.text('CLOCKED OUT'), findsOneWidget);
      expect(find.text('Last clocked out at 1:05 PM.'), findsOneWidget);
      expect(find.text('11:00 AM → 1:05 PM'), findsOneWidget);
      await dispose(tester);
    });
  }

  testWidgets('a refused punch shows the server\'s reason and fix', (tester) async {
    phone(tester);
    repo.nextFailure = AttendanceFailures.rejected(
        'outside_geofence', '489 m from the arena; the limit is 100 m');
    probe.next = FakeLocationProbe.outside;
    await tester.pumpWidget(app(const AttendanceScreen()));
    await settle(tester);
    await tester.tap(find.text('Clock in'));
    await settle(tester);
    expect(find.textContaining("You're outside the arena area (489 m"), findsOneWidget);
    expect(find.textContaining("Clock in when you're at the arena"), findsOneWidget);
    expect(find.text('Try again'), findsNothing, reason: 'a refusal is final');
    expect(find.text('Outside · 489 m away · ±8 m'), findsOneWidget);
    expect(find.text('CLOCKED OUT'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('offline: Try again resends the same punch', (tester) async {
    phone(tester);
    repo.nextFailure = AttendanceFailures.offline;
    await tester.pumpWidget(app(const AttendanceScreen()));
    await settle(tester);
    await tester.tap(find.text('Clock in'));
    await settle(tester);
    expect(find.textContaining("You're offline"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(repo.sent, hasLength(2));
    expect(repo.sent[1].punchId, repo.sent[0].punchId,
        reason: 'the server records it once whichever attempt arrives');
    expect(probe.reads, 1, reason: 'the location taken at the tap is kept');
    expect(find.text('ON THE CLOCK'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('location blocked for the app: offers the app settings', (tester) async {
    desktop(tester);
    probe.next = const LocationReading.none(LocationStatus.deniedForever);
    repo.rulesValue = const AttendanceRules(
        geofence: Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100),
        outsideRule: OutsideRule.block);
    repo.nextFailure =
        AttendanceFailures.rejected('location_required', 'location permission is off');
    await tester.pumpWidget(app(const AttendanceScreen()));
    await settle(tester);
    expect(find.textContaining('accepts clock-ins only at the arena'), findsOneWidget);
    await tester.tap(find.text('Clock in'));
    await settle(tester);
    expect(find.text('Location is blocked for this app'), findsOneWidget);
    expect(find.textContaining('needs your location'), findsOneWidget);
    await tester.tap(find.text('Open app settings'));
    expect(probe.appSettingsOpened, 1);
    await dispose(tester);
  });

  testWidgets('GPS off: offers to turn location on', (tester) async {
    phone(tester);
    probe.next = const LocationReading.none(LocationStatus.gpsOff);
    repo.nextFailure =
        AttendanceFailures.rejected('location_required', 'location services are off');
    await tester.pumpWidget(app(const AttendanceScreen()));
    await settle(tester);
    await tester.tap(find.text('Clock in'));
    await settle(tester);
    await tester.tap(find.text('Turn on location'));
    expect(probe.locationSettingsOpened, 1);
    await dispose(tester);
  });

  testWidgets('without the online arena it says so', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const AttendanceScreen(),
        repository: const UnavailableAttendanceRepository()));
    await settle(tester);
    expect(find.text(AttendanceFailures.cloudOnly.message), findsOneWidget);
    expect(find.text('Clock in'), findsNothing);
    await dispose(tester);
  });

  for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$name: history by day, with the map and punch details', (tester) async {
      size(tester);
      const fence = Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100);
      AttendancePunch p(String id, PunchKind kind, DateTime at, GeofenceVerdict v,
              {double lat = 12.9717, int distance = 11}) =>
          AttendancePunch(
              id: id,
              kind: kind,
              serverAt: at,
              lat: lat,
              lng: 77.5946,
              accuracyM: 8,
              isMocked: false,
              locationStatus: 'ok',
              distanceM: distance,
              verdict: v,
              geofence: fence);
      repo.entries.addAll([
        AttendanceEntry(
          id: 'yesterday',
          workDate: const IstDate(2026, 10, 14),
          inAt: ist(2026, 10, 14, 11, 0),
          outAt: ist(2026, 10, 14, 19, 30),
          outSource: 'punch',
          flags: const ['outside_out'],
          review: 'pending',
          inPunch: p('p1', PunchKind.clockIn, ist(2026, 10, 14, 11, 0), GeofenceVerdict.inside),
          outPunch: p('p2', PunchKind.clockOut, ist(2026, 10, 14, 19, 30),
              GeofenceVerdict.outside, lat: 12.9760, distance: 489),
        ),
        AttendanceEntry(
          id: 'morning',
          workDate: const IstDate(2026, 10, 15),
          inAt: ist(2026, 10, 15, 9, 0),
          outAt: ist(2026, 10, 15, 10, 0),
          outSource: 'punch',
          inPunch: p('p3', PunchKind.clockIn, ist(2026, 10, 15, 9, 0), GeofenceVerdict.inside),
          outPunch: p('p4', PunchKind.clockOut, ist(2026, 10, 15, 10, 0), GeofenceVerdict.inside),
        ),
      ]);
      repo.days.addAll(const [
        AttendanceDay(day: IstDate(2026, 10, 13), status: DayStatus.absent),
        AttendanceDay(day: IstDate(2026, 10, 14), status: DayStatus.present, workedMin: 510,
            entries: 1, schedMin: 480, extraMin: 30),
        AttendanceDay(day: IstDate(2026, 10, 15), status: DayStatus.upcoming, workedMin: 60, entries: 1),
      ]);
      await tester.pumpWidget(app(const AttendanceHistoryScreen()));
      await settle(tester);
      expect(find.text('Tue 13 Oct'), findsOneWidget, reason: 'an absent day shows without clock-ins');
      expect(find.text('Absent'), findsOneWidget);
      expect(find.text('No clock-in'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('8h 30m · +30m extra'), findsOneWidget,
          reason: 'the server\'s counted minutes (after the break), with extra hours');
      expect(find.text('Thu 15 Oct'), findsOneWidget);
      expect(find.text('Wed 14 Oct'), findsOneWidget);
      expect(find.text('Owner will check'), findsOneWidget);

      await tester.tap(find.text('11:00 AM → 7:30 PM'));
      await settle(tester);
      expect(find.text('Clock-in · 11:00 AM'), findsOneWidget);
      expect(find.text('Clock-out · 7:30 PM'), findsOneWidget);
      expect(find.text('Outside the arena (out)'), findsOneWidget);
      expect(find.text('GPS fix · 489 m from the arena · ±8 m'), findsOneWidget);
      expect(find.byType(PunchMap), findsOneWidget);
      expect(find.text('IN'), findsOneWidget, reason: 'clock-in pin');
      expect(find.text('OUT'), findsOneWidget, reason: 'clock-out pin');
      await dispose(tester);
    });
  }

  group('floor header chip', () {
    Widget floorHeader() => const Scaffold(body: Center(child: AttendanceChip()));

    testWidgets('clocked out: "Clock in", opens the attendance screen', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(floorHeader()));
      await settle(tester);
      expect(find.text('Clock in'), findsOneWidget);
      await tester.tap(find.byType(AttendanceChip));
      await settle(tester);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('on the clock: live time since the clock-in', (tester) async {
      desktop(tester);
      repo.entries.add(AttendanceEntry(
          id: 'open',
          workDate: const IstDate(2026, 10, 15),
          inAt: ist(2026, 10, 15, 9, 30)));
      await tester.pumpWidget(app(floorHeader()));
      await settle(tester);
      expect(find.text('On the clock · 1h 30m'), findsOneWidget);
      clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('On the clock · 1h 35m'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('hidden without the online arena', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(floorHeader(), online: false));
      await settle(tester);
      expect(find.text('Clock in'), findsNothing);
      expect(find.text('Attendance'), findsNothing);
      await dispose(tester);
    });
  });
}
