/// The Bookings tab groups open bookings by the IST business day they start on
/// and reads each one against the clock: about to start, late, or missed — and
/// only offers a check-in on the booking's own day (or after it).
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_agenda.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  // Thursday 15 Oct 2026, 6 PM IST.
  final now = ist(2026, 10, 15, 18, 0);

  Booking booking(
    String id,
    DateTime start, {
    Duration length = const Duration(hours: 1),
    BookingStatus status = BookingStatus.booked,
  }) => Booking(
    id: id,
    activityCode: 'PS5',
    scheduledStart: start,
    scheduledEnd: start.add(length),
    status: status,
    createdAt: now,
    updatedAt: now,
  );

  group('BookingTiming', () {
    test('reads a booking against the clock', () {
      expect(
        BookingTiming.of(booking('a', ist(2026, 10, 15, 20, 0)), now),
        BookingTiming.later,
      );
      expect(
        BookingTiming.of(booking('b', ist(2026, 10, 15, 19, 0)), now),
        BookingTiming.soon,
        reason: 'exactly an hour away is within the hour',
      );
      expect(
        BookingTiming.of(booking('c', ist(2026, 10, 15, 17, 30)), now),
        BookingTiming.late,
      );
      expect(
        BookingTiming.of(booking('d', ist(2026, 10, 15, 17, 0)), now),
        BookingTiming.missed,
        reason: 'the slot ended at 6 PM, which is now',
      );
    });

    test('minutes until start round up, never to zero before the start', () {
      final b = booking('a', ist(2026, 10, 15, 18, 25));
      expect(minutesUntilStart(b, now), 25);
      expect(minutesUntilStart(b, now.add(const Duration(seconds: 30))), 25);
      expect(
        minutesUntilStart(
          b,
          ist(2026, 10, 15, 18, 24).add(const Duration(seconds: 59)),
        ),
        1,
      );
      expect(minutesUntilStart(b, ist(2026, 10, 15, 18, 30)), 0);
    });
  });

  test('check-in is offered on the booking\'s day or after, never before', () {
    expect(
      canCheckInNow(booking('today', ist(2026, 10, 15, 22, 0)), now),
      isTrue,
    );
    expect(
      canCheckInNow(booking('missed', ist(2026, 10, 14, 19, 0)), now),
      isTrue,
      reason: 'a late party from yesterday can still be seated',
    );
    expect(
      canCheckInNow(booking('tomorrow', ist(2026, 10, 16, 0, 30)), now),
      isFalse,
      reason: 'checking in starts a session now',
    );
  });

  test('days read as Today, Tomorrow, Yesterday, else the date', () {
    const today = IstDate(2026, 10, 15);
    expect(bookingDayLabel(today, today), 'Today');
    expect(bookingDayLabel(const IstDate(2026, 10, 16), today), 'Tomorrow');
    expect(bookingDayLabel(const IstDate(2026, 10, 14), today), 'Yesterday');
    expect(bookingDayLabel(const IstDate(2026, 10, 17), today), 'Sat 17 Oct');
  });

  group('BookingAgenda', () {
    test('missed first, then today, tomorrow and each later day', () {
      final agenda = BookingAgenda.of([
        booking('sat', ist(2026, 10, 17, 20, 0)),
        booking('tomorrow', ist(2026, 10, 16, 19, 0)),
        booking('tonight', ist(2026, 10, 15, 21, 0)),
        booking('late', ist(2026, 10, 15, 17, 30)),
        booking('missed', ist(2026, 10, 14, 19, 0)),
        booking('sat-early', ist(2026, 10, 17, 11, 0)),
      ], now);

      expect(
        [for (final s in agenda.sections) s.label],
        ['Needs attention', 'Today', 'Tomorrow', 'Sat 17 Oct'],
      );
      expect(
        [for (final s in agenda.sections) s.bookings.map((b) => b.id)],
        [
          ['missed'],
          ['late', 'tonight'],
          ['tomorrow'],
          ['sat-early', 'sat'],
        ],
      );
      expect(agenda.sections.first.needsAttention, isTrue);
      expect(
        agenda.nextToday?.id,
        'tonight',
        reason: 'the late one has already started',
      );
    });

    test('a slot that began before midnight and is still running is today', () {
      final justAfterMidnight = ist(2026, 10, 16, 0, 15);
      final agenda = BookingAgenda.of([
        booking('night', ist(2026, 10, 15, 23, 30)),
      ], justAfterMidnight);

      expect(agenda.missed, isEmpty);
      expect(agenda.today.single.id, 'night');
      expect(agenda.nextToday, isNull);
    });

    test('only still-booked reservations are listed', () {
      final agenda = BookingAgenda.of([
        booking(
          'in',
          ist(2026, 10, 15, 17, 0),
          status: BookingStatus.checkedIn,
        ),
        booking(
          'off',
          ist(2026, 10, 15, 20, 0),
          status: BookingStatus.cancelled,
        ),
        booking('gone', ist(2026, 10, 15, 16, 0), status: BookingStatus.noShow),
      ], now);

      expect(agenda.isEmpty, isTrue);
      expect(agenda.sections, isEmpty);
    });
  });
}
