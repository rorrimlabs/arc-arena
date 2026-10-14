/// Session timer alerts (5 min, 1 min, time up) are scheduled with the OS, so
/// they ring with the app in the background or closed. These pin what keeps
/// them right: an app restart puts them back after its clean-up, a session
/// ended or extended on another device moves them (through sync → refresh),
/// a station switch renames them, and a phone whose clock is off still rings
/// at the arena's time.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/notifications/device_time.dart';
import 'package:arena_ops/app/notifications/reminder_startup.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pricing_fixtures.dart';
import '../support/test_db.dart';

/// The OS scheduler, recorded in order.
class _Os implements NotificationService {
  final events = <String>[];
  final scheduled = <int, ReminderPlan>{};

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    events.add('permission');
    return true;
  }

  @override
  Future<void> schedule(ReminderPlan plan) async {
    events.add('schedule ${plan.id}');
    scheduled[plan.id] = plan;
  }

  @override
  Future<void> showInstant(ReminderPlan plan) async {}
  @override
  Future<void> cancel(int id) async {
    events.add('cancel $id');
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    events.add('cancelAll');
    scheduled.clear();
  }

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();
}

void main() {
  late AppDatabase db;
  late _Os os;
  late ProviderContainer app;
  late FakeClock floorClock;
  final start = ist(2026, 10, 2, 18, 0); // Friday 18:00 IST.

  ProviderContainer containerFor(Clock clock) => ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(os),
      authControllerProvider.overrideWith(TestOwnerAuth.new),
      clockProvider.overrideWithValue(clock),
    ],
  );

  setUp(() async {
    db = await seededMemoryDb();
    os = _Os();
    floorClock = FakeClock(start);
    app = containerFor(floorClock);
  });
  tearDown(() async {
    app.dispose();
    await db.close();
  });

  Future<Session> startOn(
    ProviderContainer c, {
    String station = 'hex',
    String name = 'HEX',
    int minutes = 60,
  }) async {
    final who = await c
        .read(customerRepositoryProvider)
        .create(name: 'Arjun', phone: '9000000009');
    final r = await c.read(sessionActionsProvider).start(
      NewSessionDraft(
        customerId: who.id,
        activityCode: 'PS5',
        resourceId: station,
        resourceName: name,
        durationMinutes: minutes,
        controllerCount: 1,
      ),
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    await pumpEventQueue(); // scheduling is fire-and-forget
    return r.valueOrNull!;
  }

  Set<int> slots(String id) => {for (var s = 0; s < 3; s++) sessionAlertId(id, s)};

  /// Another device's actions: same database (as after sync), but its alerts
  /// are that device's business — nothing is scheduled or cancelled here.
  SessionActions otherDevice(ProviderContainer c) => SessionActions(
    sessions: c.read(sessionRepositoryProvider),
    groups: c.read(groupSessionRepositoryProvider),
    catalog: c.read(catalogRepositoryProvider),
    bookings: c.read(bookingRepositoryProvider),
    clock: c.read(clockProvider),
    guard: PermissionGuard(c.read(authControllerProvider)),
    pads: c.read(controllerAllocationRepositoryProvider),
  );

  test('starting a session schedules all three alerts', () async {
    final s = await startOn(app);
    expect(os.scheduled.keys.toSet(), slots(s.id));
    expect(os.scheduled[sessionAlertId(s.id, 2)]!.fireAtUtc, s.scheduledEndAt);
  });

  test('after an app restart, running sessions ring again, and what the last '
      'run left for ended sessions is swept', () async {
    final s = await startOn(app);
    app.dispose();
    // Left by the last run: the alerts of a session that ended meanwhile.
    final stale = slots('ended-while-closed');
    for (final id in stale) {
      os.scheduled[id] = ReminderPlan(
        id: id,
        sessionId: 'ended-while-closed',
        fireAtUtc: start.add(const Duration(hours: 2)),
        title: 'stale',
        body: 'stale',
      );
    }
    os.events.clear();

    app = containerFor(FakeClock(start.add(const Duration(minutes: 20))));
    await startReminders(app);

    expect(os.events.first, 'permission');
    for (final id in slots(s.id)) {
      expect(os.events, contains('schedule $id'));
    }
    expect(os.scheduled.keys.toSet(), slots(s.id));
    for (final id in stale) {
      expect(os.events, contains('cancel $id'));
    }
  });

  test('a refresh replaces alerts in place: it never cancels a running '
      "session's alert first (one due during the rebuild still rings)",
      () async {
    final s = await startOn(app);
    os.events.clear();

    await refreshReminders(app);

    expect(os.events, isNot(contains('cancelAll')));
    for (final id in slots(s.id)) {
      expect(os.events, isNot(contains('cancel $id')));
      expect(os.events, contains('schedule $id'));
    }
  });

  test('a session ended on another device: the refresh after sync cancels its '
      'alerts', () async {
    final s = await startOn(app);
    final a = (await app.read(sessionRepositoryProvider).active()).single;
    final ended = await otherDevice(app).end(a.session, a.segments);
    expect(ended.isOk, isTrue, reason: ended.failureOrNull?.display);
    expect(os.scheduled.keys.toSet(), slots(s.id), reason: 'still stale');

    await app.read(sessionRemindersProvider).reconcile();

    for (final id in slots(s.id)) {
      expect(os.events, contains('cancel $id'));
    }
    expect(os.scheduled, isEmpty);
  });

  test('extended on another device: the time-up alert moves to the new end',
      () async {
    final s = await startOn(app);
    final a = (await app.read(sessionRepositoryProvider).active()).single;
    final extended = await otherDevice(app).extend(a.session, a.segments, 30);
    expect(extended.isOk, isTrue, reason: extended.failureOrNull?.display);

    await refreshReminders(app);

    expect(
      os.scheduled[sessionAlertId(s.id, 2)]!.fireAtUtc,
      s.scheduledEndAt.add(const Duration(minutes: 30)),
    );
  });

  test('a refresh running while this device extends never puts the old end '
      'back', () async {
    final s = await startOn(app);
    final reminders = app.read(sessionRemindersProvider);
    final a = (await app.read(sessionRepositoryProvider).active()).single;

    final refreshing = reminders.reconcile(); // e.g. sync just pulled rows
    final extended =
        await app.read(sessionActionsProvider).extend(a.session, a.segments, 30);
    expect(extended.isOk, isTrue, reason: extended.failureOrNull?.display);
    await refreshing;
    await reminders.cancelFor('settle'); // runs after everything queued

    expect(
      os.scheduled[sessionAlertId(s.id, 2)]!.fireAtUtc,
      s.scheduledEndAt.add(const Duration(minutes: 30)),
    );
  });

  test('an extension the server refused moves the end back: the later 5-min '
      'alert no longer rings, the ones still ahead stay', () async {
    final s = await startOn(app); // ends 19:00
    final a = (await app.read(sessionRepositoryProvider).active()).single;
    final ext = await app.read(sessionActionsProvider).extend(a.session, a.segments, 30);
    expect(ext.isOk, isTrue, reason: ext.failureOrNull?.display);
    await app.read(sessionRemindersProvider).cancelFor('settle');
    expect(
      os.scheduled[sessionAlertId(s.id, 0)]!.fireAtUtc,
      ist(2026, 10, 2, 19, 25),
    );

    floorClock.set(ist(2026, 10, 2, 18, 57));
    // The refused extension is rolled back: the end is 19:00 again.
    await (db.update(db.sessions)..where((t) => t.id.equals(s.id))).write(
      SessionsCompanion(scheduledEndAt: Value(s.scheduledEndAt)),
    );
    os.events.clear();
    await app.read(sessionRemindersProvider).reconcile();

    expect(os.events, contains('cancel ${sessionAlertId(s.id, 0)}'),
        reason: 'its 5-min mark (18:55) has passed; 19:25 must not ring');
    expect(os.scheduled[sessionAlertId(s.id, 1)]!.fireAtUtc,
        ist(2026, 10, 2, 18, 59));
    expect(os.scheduled[sessionAlertId(s.id, 2)]!.fireAtUtc, s.scheduledEndAt);
  });

  test('an alert already due is never cancelled by a refresh', () async {
    final s = await startOn(app);
    // Just past the 5-min mark: the OS may still be about to ring it.
    floorClock.set(ist(2026, 10, 2, 18, 55).add(const Duration(milliseconds: 50)));
    os.events.clear();
    await refreshReminders(app);
    expect(os.events, isNot(contains('cancel ${sessionAlertId(s.id, 0)}')));
  });

  test('checking in a booking starts its session\'s timer alerts', () async {
    final who = await app
        .read(customerRepositoryProvider)
        .create(name: 'Meera', phone: '9000000010');
    final booked = await app.read(bookingActionsProvider).createBooking(
      BookingDraft(
        customerId: who.id,
        activityCode: 'PS5',
        date: IstDate(2026, 10, 2),
        startMinuteOfDay: 19 * 60,
        durationMinutes: 60,
        gameId: 'g_eafc',
        resourceId: 'void',
        controllerRequirement: 1,
      ),
    );
    expect(booked.isOk, isTrue, reason: booked.failureOrNull?.display);
    floorClock.set(ist(2026, 10, 2, 19, 5));

    final r = await app.read(bookingActionsProvider).checkIn(booked.valueOrNull!);
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    await app.read(sessionRemindersProvider).cancelFor('settle');

    expect(os.scheduled.keys, containsAll(slots(r.valueOrNull!.id)));
  });

  test('the start-up sweep is skipped when the rebuild failed (it would '
      'cancel good alerts)', () async {
    final s = await startOn(app);
    app.dispose();
    final broken = await seededMemoryDb();
    await broken.close();
    app = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(broken),
        notificationServiceProvider.overrideWithValue(os),
        authControllerProvider.overrideWith(TestOwnerAuth.new),
        clockProvider.overrideWithValue(floorClock),
      ],
    );
    os.events.clear();

    await startReminders(app);

    for (final id in slots(s.id)) {
      expect(os.events, isNot(contains('cancel $id')));
      expect(os.scheduled.keys, contains(id));
    }
  });

  test('switching station renames the alerts', () async {
    final s = await startOn(app);
    final a = (await app.read(sessionRepositoryProvider).active()).single;
    final moved = await app.read(sessionActionsProvider).switchSystem(
      session: a.session,
      current: a.current,
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      controllerCount: 1,
    );
    expect(moved.isOk, isTrue, reason: moved.failureOrNull?.display);
    await pumpEventQueue();

    expect(os.scheduled[sessionAlertId(s.id, 2)]!.title, contains('VOID'));
  });

  test('a phone 10 minutes slow still rings at the arena\'s time', () async {
    // App time follows the server: device + 10 min.
    final device = FakeClock(start);
    app.dispose();
    app = containerFor(OffsetClock(device, const Duration(minutes: 10)));

    final s = await startOn(app);
    final timeUp = os.scheduled[sessionAlertId(s.id, 2)]!;
    expect(
      timeUp.fireAtUtc,
      s.scheduledEndAt.subtract(const Duration(minutes: 10)),
      reason: 'the OS fires on the DEVICE clock, which reads 10 min less',
    );
  });

  test('onDeviceClock leaves plans alone when the device clock is trusted', () {
    final plan = ReminderPlan(
      id: 1,
      fireAtUtc: DateTime.utc(2026, 10, 2, 13),
      title: 't',
      body: 'b',
    );
    expect(onDeviceClock(plan, FakeClock(start)), same(plan));
    expect(
      onDeviceClock(plan, OffsetClock(FakeClock(start), Duration.zero)),
      same(plan),
    );
    expect(
      onDeviceClock(
        plan,
        OffsetClock(FakeClock(start), const Duration(minutes: -5)),
      ).fireAtUtc,
      DateTime.utc(2026, 10, 2, 13, 5),
      reason: 'a phone running fast rings later by its own clock',
    );
  });
}
