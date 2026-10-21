/// This phone's alert settings: anyone (staff included) can see whether the
/// phone blocks the app and fix it, turn alerts on or off, and hear a test —
/// and a change moves the alerts already set for running sessions at once.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_notification_settings_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/features/more/presentation/more_screen.dart';
import 'package:arena_ops/features/notifications/presentation/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

/// The phone: what it allows, and every alert asked of it.
class _Phone implements NotificationService {
  bool? allowed = true;
  bool? exactAlarms = true;
  final events = <String>[];
  final scheduled = <int, ReminderPlan>{};

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    events.add('permission');
    return allowed ?? false;
  }

  @override
  Future<bool?> notificationsAllowed() async => allowed;
  @override
  Future<bool?> exactAlarmsAllowed() async => exactAlarms;
  @override
  Future<bool> requestExactAlarms() async {
    events.add('exact alarms');
    return false;
  }

  @override
  Future<bool> openSystemSettings() async {
    events.add('phone settings');
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
  Future<void> cancelAll() async => scheduled.clear();
  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();
}

void main() {
  late AppDatabase db;
  late _Phone phone;
  final start = ist(2026, 10, 2, 18, 0); // Friday 18:00 IST.

  setUp(() async {
    db = await seededMemoryDb();
    phone = _Phone();
  });
  tearDown(() async => db.close());

  const phoneSize = (Size(1179, 2556), 3.0);
  const desktopSize = (Size(2560, 1600), 2.0);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required (Size, double) size,
    AuthController Function() auth = TestOwnerAuth.new,
  }) async {
    tester.view.physicalSize = size.$1;
    tester.view.devicePixelRatio = size.$2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(phone),
          authControllerProvider.overrideWith(auth),
          clockProvider.overrideWithValue(FakeClock(start)),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pump();
    await tester.tap(find.text(text));
    await settle(tester);
  }

  /// A session running on HEX until 19:00 whose three alerts an earlier run
  /// of the app set (the phone still holds them).
  Future<String> runningSession() async {
    final catalog = LocalCatalogRepository(db);
    final kabir = await LocalCustomerRepository(
      db,
      FakeClock(start),
    ).create(name: 'Kabir');
    final r = await LocalSessionRepository(db, FakeClock(start)).start(
      StartSessionCommand(
        customerId: kabir.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: await catalog.currentSnapshot(),
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerCount: 1,
      ),
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    final id = r.valueOrNull!.id;
    for (final plan in buildSessionAlerts(
      sessionId: id,
      titleName: 'HEX (Kabir)',
      scheduledEndAt: start.add(const Duration(hours: 1)),
      now: start,
    )) {
      phone.scheduled[plan.id] = plan;
    }
    return id;
  }

  Switch switchOf(WidgetTester tester, String title) => tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
      matching: find.byType(Switch),
    ),
  );

  for (final (name, size) in [('phone', phoneSize), ('desktop', desktopSize)]) {
    testWidgets('blocked by the phone: Allow, then the way to its settings '
        '($name)', (tester) async {
      phone
        ..allowed = false
        ..exactAlarms = false;
      await pump(tester, const NotificationSettingsScreen(), size: size);

      expect(find.text('Blocked by the phone'), findsOneWidget);
      expect(find.text('Alerts may come late'), findsOneWidget);
      expect(find.text('Open phone settings'), findsNothing);

      await tap(tester, 'Allow notifications');
      expect(phone.events, contains('permission'));
      // The phone still says no (it no longer asks): its settings are next.
      expect(find.text('Open phone settings'), findsOneWidget);
      expect(
        find.textContaining('Notifications and switch them on'),
        findsOneWidget,
      );
      await tap(tester, 'Open phone settings');
      expect(phone.events, contains('phone settings'));

      await tap(tester, 'Allow alarms on time');
      expect(phone.events, contains('exact alarms'));
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('a switch saves at once and moves the running session\'s '
        'alerts; the test alert rings like time up ($name)', (tester) async {
      final session = await runningSession();
      await pump(tester, const NotificationSettingsScreen(), size: size);

      expect(find.text('Notifications are on for this phone'), findsOneWidget);
      expect(find.text('Alerts may come late'), findsNothing);

      await tap(tester, '1 minute before');
      final settings = LocalNotificationSettingsRepository(db);
      expect((await settings.getSettings()).alert1Min, isFalse);
      expect(
        phone.events,
        contains('cancel ${sessionAlertId(session, 1)}'),
        reason: 'set by an earlier run, still ahead, now off',
      );
      expect(phone.scheduled.keys, isNot(contains(sessionAlertId(session, 1))));

      await tap(tester, 'Sound');
      expect((await settings.getSettings()).soundEnabled, isFalse);
      final timeUp = phone.scheduled[sessionAlertId(session, 2)]!;
      expect(timeUp.playSound, isFalse, reason: 'rescheduled without sound');

      phone.events.clear();
      await tap(tester, 'Send a test alert');
      final tests = phone.events
          .where((e) => e.startsWith('schedule'))
          .toList();
      expect(tests, ['schedule $testAlertId']);
      final test = phone.scheduled[testAlertId]!;
      expect(test.kind, AlertKind.timeUp);
      expect(test.playSound, isFalse, reason: 'with the current settings');
      expect(test.fireAtUtc, start.add(const Duration(seconds: 5)));
      expect(find.textContaining('Test alert in 5 seconds'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Booking reminders ring 30 min before each booking.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('timer alerts off: the per-alert switches are disabled and '
        'every alert still ahead is cancelled ($name)', (tester) async {
      final session = await runningSession();
      await pump(tester, const NotificationSettingsScreen(), size: size);
      expect(switchOf(tester, '5 minutes before').onChanged, isNotNull);

      await tap(tester, 'Timer alerts');

      expect(switchOf(tester, 'Timer alerts').value, isFalse);
      for (final title in [
        '5 minutes before',
        '1 minute before',
        'When time is up',
        'Sound',
        'Vibrate',
        'Keep ringing until opened',
      ]) {
        expect(switchOf(tester, title).onChanged, isNull, reason: title);
      }
      for (var slot = 0; slot < 3; slot++) {
        expect(
          phone.scheduled.keys,
          isNot(contains(sessionAlertId(session, slot))),
        );
      }
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('More shows the Notifications row to staff ($name)', (
      tester,
    ) async {
      await pump(
        tester,
        const MoreScreen(),
        size: size,
        auth: TestStaffAuth.new,
      );

      expect(find.text('Notifications'), findsOneWidget);
      expect(
        find.text('Timer alerts on · 5 min, 1 min, time up'),
        findsOneWidget,
      );

      await tap(tester, 'Notifications');
      expect(
        find.text('Timer alerts'),
        findsOneWidget,
        reason: 'the settings screen opened',
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets('More says when the phone blocks alerts, or they are off', (
    tester,
  ) async {
    phone.allowed = false;
    await pump(
      tester,
      const MoreScreen(),
      size: phoneSize,
      auth: TestStaffAuth.new,
    );
    expect(find.text('Blocked by the phone'), findsOneWidget);
    await close(tester);

    phone.allowed = true;
    await LocalNotificationSettingsRepository(db)
        .saveSettings(const NotificationSettings(enabled: false));
    await pump(
      tester,
      const MoreScreen(),
      size: phoneSize,
      auth: TestStaffAuth.new,
    );
    expect(find.text('Timer alerts off'), findsOneWidget);
    await close(tester);
  });
}
