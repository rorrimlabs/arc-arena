import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const svc = AvailabilityService();
  final close = ist(2026, 10, 2, 23, 0); // 11:00 PM

  UtcInterval win(int fromH, int fromM, int toH, int toM) =>
      UtcInterval(ist(2026, 10, 2, fromH, fromM), ist(2026, 10, 2, toH, toM));

  Occupancy session(String res, int fromH, int fromM, int toH, int toM,
          {String? label}) =>
      Occupancy(resourceId: res, interval: win(fromH, fromM, toH, toM), isBooking: false, label: label);

  Occupancy booking(String res, int fromH, int fromM, int toH, int toM) =>
      Occupancy(resourceId: res, interval: win(fromH, fromM, toH, toM), isBooking: true);

  group('canStart', () {
    test('free resource within hours → ok', () {
      final r = svc.canStart(
        resourceId: 'void',
        resourceName: 'VOID',
        window: win(18, 0, 19, 0),
        occupancies: const [],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isOk, isTrue);
    });

    test('overlapping active session → resource_busy', () {
      final r = svc.canStart(
        resourceId: 'void',
        resourceName: 'VOID',
        window: win(18, 30, 19, 30),
        occupancies: [session('void', 18, 0, 19, 0, label: 'Rahul')],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'resource_busy');
      expect(r.failureOrNull!.message, contains('VOID'));
    });

    test('touching an existing session is allowed (half-open)', () {
      final r = svc.canStart(
        resourceId: 'void',
        resourceName: 'VOID',
        window: win(19, 0, 20, 0),
        occupancies: [session('void', 18, 0, 19, 0)],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isOk, isTrue);
    });

    test('a different resource does not conflict', () {
      final r = svc.canStart(
        resourceId: 'hex',
        resourceName: 'HEX',
        window: win(18, 30, 19, 30),
        occupancies: [session('void', 18, 0, 19, 0)],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isOk, isTrue);
    });

    test('past closing time is blocked unless allowed', () {
      final r = svc.canStart(
        resourceId: 'hex',
        resourceName: 'HEX',
        window: win(22, 30, 23, 30),
        occupancies: const [],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'past_close');

      final allowed = svc.canStart(
        resourceId: 'hex',
        resourceName: 'HEX',
        window: win(22, 30, 23, 30),
        occupancies: const [],
        closeAt: close,
        allowPastClose: true,
      );
      expect(allowed.isOk, isTrue);
    });

    test('RIFT: a PS5 session blocks a VR start (PS5 ⊕ VR, spec §13)', () {
      // Same resource id "rift" regardless of activity.
      final r = svc.canStart(
        resourceId: 'rift',
        resourceName: 'RIFT',
        window: win(18, 0, 18, 30),
        occupancies: [session('rift', 17, 30, 19, 0)], // active PS5
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull?.code, 'resource_busy');
    });
  });

  group('maxExtension', () {
    test('capped by the next booking', () {
      final limit = svc.maxExtension(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 19, 0),
        occupancies: [booking('hex', 19, 30, 20, 30)],
        closeAt: close,
        allowPastClose: false,
      );
      expect(limit.maxMinutes, 30);
      expect(limit.blockedByBooking, isTrue);
    });

    test('touching booking → zero extension', () {
      final limit = svc.maxExtension(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 19, 0),
        occupancies: [booking('hex', 19, 0, 20, 0)],
        closeAt: close,
        allowPastClose: false,
      );
      expect(limit.maxMinutes, 0);
    });

    test('capped by closing time when no bookings', () {
      final limit = svc.maxExtension(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 22, 20),
        occupancies: const [],
        closeAt: close,
        allowPastClose: false,
      );
      expect(limit.maxMinutes, 40);
      expect(limit.blockedByBooking, isFalse);
    });

    test('unbounded when past-close allowed and no bookings', () {
      final limit = svc.maxExtension(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 22, 20),
        occupancies: const [],
        closeAt: close,
        allowPastClose: true,
      );
      expect(limit.unbounded, isTrue);
    });
  });

  group('canExtend (spec §13 example)', () {
    // Current 6:00–7:00 PM, next booking 7:00–8:00 PM, attempt +30 → BLOCKED.
    final currentEnd = ist(2026, 10, 2, 19, 0);
    final occ = [booking('hex', 19, 0, 20, 0)];

    test('+30 is blocked with the exact message', () {
      final r = svc.canExtend(
        resourceId: 'hex',
        currentEnd: currentEnd,
        addedMinutes: 30,
        occupancies: occ,
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, "Can't extend past 7:00 PM. This station is booked.");
    });

    test('reports the available extension amount', () {
      final r = svc.canExtend(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 19, 0),
        addedMinutes: 30,
        occupancies: [booking('hex', 19, 20, 20, 0)], // 20 min gap
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.fix, 'Only +20 min is available.');
    });

    test('a valid extension returns the new end', () {
      final r = svc.canExtend(
        resourceId: 'hex',
        currentEnd: ist(2026, 10, 2, 19, 0),
        addedMinutes: 30,
        occupancies: const [],
        closeAt: close,
        allowPastClose: false,
      );
      expect(r.isOk, isTrue);
      expect(r.valueOrNull, ist(2026, 10, 2, 19, 30));
    });
  });
}
