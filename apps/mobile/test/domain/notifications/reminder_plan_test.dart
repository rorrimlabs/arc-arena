import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 7:00 PM IST == 13:30 UTC.
  final start = DateTime.utc(2026, 10, 10, 13, 30);
  Booking booking({String? resourceId, String? gameId = 'g_eafc'}) => Booking(
        id: 'bk_123',
        customerId: 'c1',
        activityCode: 'PS5',
        gameId: gameId,
        resourceId: resourceId,
        scheduledStart: start,
        scheduledEnd: start.add(const Duration(hours: 1)),
        playersRequired: 2,
        controllerRequirement: 2,
        status: BookingStatus.booked,
        createdAt: start.subtract(const Duration(days: 1)),
        updatedAt: start.subtract(const Duration(days: 1)),
      );

  group('reminderId', () {
    test('is deterministic, positive, and distinct per slot', () {
      expect(reminderId('bk_123', 0), reminderId('bk_123', 0));
      expect(reminderId('bk_123', 0), isNonNegative);
      expect(reminderId('bk_123', 0) <= 0x7fffffff, isTrue);
      expect(reminderId('bk_123', 0), isNot(reminderId('bk_123', 1)));
      expect(reminderId('bk_123', 0), isNot(reminderId('bk_456', 0)));
    });
  });

  group('buildBookingReminders', () {
    test('30-min lead reminder with the spec message (§23)', () {
      final now = DateTime.utc(2026, 10, 10, 10, 0); // 3h before start
      final plans = buildBookingReminders(
        booking: booking(),
        customerName: 'Rahul',
        activityLabel: 'PS5',
        gameName: 'EA FC',
        now: now,
      );
      expect(plans, hasLength(1));
      final p = plans.single;
      // Fires 30 minutes before 13:30 UTC.
      expect(p.fireAtUtc, DateTime.utc(2026, 10, 10, 13, 0));
      expect(p.body, 'Rahul — PS5 — EA FC — 7:00 PM');
      expect(p.id, reminderId('bk_123', 0));
      expect(p.title, 'Booking in 30 min');
    });

    test('includes the specific station when one is booked', () {
      final now = DateTime.utc(2026, 10, 10, 10, 0);
      final plans = buildBookingReminders(
        booking: booking(resourceId: 'void'),
        customerName: 'Rahul',
        activityLabel: 'PS5',
        gameName: 'EA FC',
        resourceName: 'VOID',
        now: now,
      );
      expect(plans.single.body, 'Rahul — PS5 — EA FC — VOID — 7:00 PM');
    });

    test('no reminder when the lead time has already passed', () {
      final now = DateTime.utc(2026, 10, 10, 13, 15); // only 15 min before
      final plans = buildBookingReminders(
        booking: booking(),
        customerName: 'Rahul',
        activityLabel: 'PS5',
        gameName: 'EA FC',
        now: now,
      );
      expect(plans, isEmpty);
    });

    test('alsoAtStart adds a second reminder at the start time', () {
      final now = DateTime.utc(2026, 10, 10, 10, 0);
      final plans = buildBookingReminders(
        booking: booking(),
        customerName: 'Rahul',
        activityLabel: 'PS5',
        gameName: 'EA FC',
        policy: const ReminderPolicy(leadMinutes: 30, alsoAtStart: true),
        now: now,
      );
      expect(plans, hasLength(2));
      expect(plans[0].fireAtUtc, DateTime.utc(2026, 10, 10, 13, 0));
      expect(plans[1].fireAtUtc, start);
      expect(plans[1].id, reminderId('bk_123', 1));
    });
  });
  group('buildSessionAlerts', () {
    // Ends 7:00 PM IST; now is 6:00 PM IST.
    final end = start;
    final now = start.subtract(const Duration(hours: 1));
    List<ReminderPlan> alerts(NotificationSettings settings, {DateTime? at}) =>
        buildSessionAlerts(
          sessionId: 's1',
          titleName: 'HEX (Rahul)',
          scheduledEndAt: end,
          now: at ?? now,
          settings: settings,
        );

    test('5 min, 1 min and time up, in slot order, at the right times', () {
      final plans = alerts(const NotificationSettings());
      expect([for (final p in plans) p.id],
          [for (var s = 0; s < 3; s++) sessionAlertId('s1', s)]);
      expect([for (final p in plans) p.fireAtUtc], [
        end.subtract(const Duration(minutes: 5)),
        end.subtract(const Duration(minutes: 1)),
        end,
      ]);
      expect([for (final p in plans) p.kind],
          [AlertKind.warning, AlertKind.warning, AlertKind.timeUp]);
      expect(plans.last.title, 'Time Expired: HEX (Rahul)');
    });

    test('nothing at all while timer alerts are off', () {
      expect(alerts(const NotificationSettings(enabled: false)), isEmpty);
    });

    test('each slot follows its own switch', () {
      final plans = alerts(const NotificationSettings(alert5Min: false));
      expect([for (final p in plans) p.id],
          [sessionAlertId('s1', 1), sessionAlertId('s1', 2)]);
      expect(
        alerts(const NotificationSettings(alertAtEnd: false))
            .map((p) => p.kind),
        everyElement(AlertKind.warning),
      );
    });

    test('only time up rings until seen, and only when that is on', () {
      final on = alerts(const NotificationSettings());
      expect([for (final p in on) p.ringUntilSeen], [false, false, true]);
      final off = alerts(const NotificationSettings(ringUntilSeen: false));
      expect(off.map((p) => p.ringUntilSeen), everyElement(isFalse));
    });

    test('sound and vibration are carried to every alert', () {
      final plans = alerts(const NotificationSettings(
        soundEnabled: false,
        vibrationEnabled: false,
      ));
      expect(plans.map((p) => p.playSound), everyElement(isFalse));
      expect(plans.map((p) => p.enableVibration), everyElement(isFalse));
    });

    test('an alert whose time has passed is left out', () {
      final plans = alerts(
        const NotificationSettings(),
        at: end.subtract(const Duration(minutes: 3)),
      );
      expect([for (final p in plans) p.id],
          [sessionAlertId('s1', 1), sessionAlertId('s1', 2)]);
    });

    test('sessionAlertWanted needs the master switch and the slot', () {
      const off = NotificationSettings(enabled: false);
      expect([for (var s = 0; s < 3; s++) sessionAlertWanted(off, s)],
          [false, false, false]);
      const some = NotificationSettings(alert1Min: false);
      expect([for (var s = 0; s < 3; s++) sessionAlertWanted(some, s)],
          [true, false, true]);
    });
  });

  test('the test alert rings like time up 5 seconds on, with the settings',
      () {
    final now = DateTime.utc(2026, 10, 10, 12);
    final plan = buildTestAlert(
      now: now,
      settings: const NotificationSettings(vibrationEnabled: false),
    );
    expect(plan.id, testAlertId);
    expect(plan.kind, AlertKind.timeUp);
    expect(plan.fireAtUtc, now.add(const Duration(seconds: 5)));
    expect(plan.enableVibration, isFalse);
    expect(plan.playSound, isTrue);
    expect(plan.ringUntilSeen, isTrue);
  });
}
