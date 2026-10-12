import 'package:arena_ops/domain/entities/booking.dart';
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
}
