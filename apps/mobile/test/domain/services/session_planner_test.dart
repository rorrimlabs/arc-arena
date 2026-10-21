import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/services/session_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const planner = SessionPlanner();
  final close = ist(2026, 10, 2, 23, 0);

  Occupancy occ(String res, int fromH, int fromM, int toH, int toM,
          {bool booking = false}) =>
      Occupancy(
        resourceId: res,
        interval: UtcInterval(
          ist(2026, 10, 2, fromH, fromM),
          ist(2026, 10, 2, toH, toM),
        ),
        isBooking: booking,
      );

  group('planStart', () {
    test('builds a price preview for a 60-min PS5 2c session (₹280)', () {
      final r = planner.planStart(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 2,
        resourceId: 'hex',
        resourceName: 'HEX',
        startedAt: ist(2026, 10, 2, 18, 15),
        durationMinutes: 60,
        occupancies: const [],
        closeAt: close,
      );
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      final plan = r.valueOrNull!;
      expect(plan.scheduledEndAt, ist(2026, 10, 2, 19, 15));
      expect(plan.quote.amount, const Paise(28000));
      expect(plan.openEnded, isFalse);
    });

    test('open-ended schedules to closing time', () {
      final r = planner.planStart(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 1,
        resourceId: 'hex',
        resourceName: 'HEX',
        startedAt: ist(2026, 10, 2, 22, 0),
        durationMinutes: null,
        occupancies: const [],
        closeAt: close,
      );
      expect(r.isOk, isTrue);
      expect(r.valueOrNull!.openEnded, isTrue);
      expect(r.valueOrNull!.scheduledEndAt, close);
    });

    test('blocks a start on an occupied resource', () {
      final r = planner.planStart(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 1,
        resourceId: 'hex',
        resourceName: 'HEX',
        startedAt: ist(2026, 10, 2, 18, 0),
        durationMinutes: 60,
        occupancies: [occ('hex', 17, 30, 18, 30)],
        closeAt: close,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'resource_busy');
    });
  });

  group('planExtension (spec §13)', () {
    test('+30 on a PS5 1c session shows old/new end and added ₹75', () {
      final start = ist(2026, 10, 2, 18, 0);
      final currentEnd = ist(2026, 10, 2, 19, 0);
      final r = planner.planExtension(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 1,
        resourceId: 'hex',
        startedAt: start,
        currentEnd: currentEnd,
        addedMinutes: 30,
        occupancies: const [],
        closeAt: close,
      );
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      final plan = r.valueOrNull!;
      expect(plan.oldEnd, currentEnd);
      expect(plan.newEnd, ist(2026, 10, 2, 19, 30));
      expect(plan.addedMinutes, 30);
      expect(plan.addedCost, const Paise(7500)); // 30 min of ₹150/hr
    });

    test('blocked extension surfaces the booking message', () {
      final r = planner.planExtension(
        snapshot: currentSnapshot(),
        activityCode: 'PS5',
        controllerCount: 1,
        resourceId: 'hex',
        startedAt: ist(2026, 10, 2, 18, 0),
        currentEnd: ist(2026, 10, 2, 19, 0),
        addedMinutes: 30,
        occupancies: [occ('hex', 19, 0, 20, 0, booking: true)],
        closeAt: close,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('This station is booked.'));
    });
  });
}
