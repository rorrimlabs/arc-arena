/// How open bookings read against the clock: which business day they fall on,
/// whether they are about to start, late or missed, and whether they can be
/// checked in now. Pure Dart, so the Bookings tab and the booking cards agree
/// and the rules are tested without a widget.
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

/// Where a booking stands against [now], for the card's timing line.
enum BookingTiming {
  /// More than an hour away.
  later,

  /// Starts within the hour.
  soon,

  /// The slot has started and nobody has checked in.
  late,

  /// The whole slot has passed without a check-in. It no longer holds the
  /// station; staff mark it no-show or cancel it.
  missed;

  static BookingTiming of(Booking booking, DateTime now) {
    if (!booking.scheduledEnd.isAfter(now)) return missed;
    if (!booking.scheduledStart.isAfter(now)) return late;
    if (booking.scheduledStart.difference(now) <= const Duration(hours: 1)) {
      return soon;
    }
    return later;
  }
}

/// Whole minutes until [booking] starts, rounded up so a booking a few seconds
/// away never reads "Starts in 0 min".
int minutesUntilStart(Booking booking, DateTime now) {
  final seconds = booking.scheduledStart.difference(now).inSeconds;
  return seconds <= 0 ? 0 : (seconds + 59) ~/ 60;
}

/// Checking in starts a session now, so only a booking for today (or an
/// earlier day, when the party turns up late) offers it. A booking for a later
/// day must wait for its day.
bool canCheckInNow(Booking booking, DateTime now) =>
    IstDate.fromUtc(booking.scheduledStart).compareTo(IstDate.fromUtc(now)) <=
    0;

/// How a business day reads: "Today", "Tomorrow", "Yesterday", else
/// "Sat 17 Oct".
String bookingDayLabel(IstDate day, IstDate today) {
  if (day == today) return 'Today';
  if (day == today.addDays(1)) return 'Tomorrow';
  if (day == today.addDays(-1)) return 'Yesterday';
  return DateFormat('EEE d MMM')
      .format(DateTime.utc(day.year, day.month, day.day));
}

/// One labelled group of bookings on the Bookings tab.
@immutable
class BookingSection {
  const BookingSection({
    required this.label,
    required this.bookings,
    this.needsAttention = false,
  });

  final String label;
  final List<Booking> bookings;

  /// The missed bookings, which can come from any earlier day.
  final bool needsAttention;
}

/// Still-booked reservations grouped for the Bookings tab, by the IST business
/// day they start on. Checked-in, cancelled and no-show bookings are left out.
@immutable
class BookingAgenda {
  const BookingAgenda._({
    required this.missed,
    required this.today,
    required this.upcoming,
    required this.nextToday,
  });

  factory BookingAgenda.of(Iterable<Booking> bookings, DateTime now) {
    final open = bookings.where((b) => b.isOpen).toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final todayDate = IstDate.fromUtc(now);

    final missed = <Booking>[];
    final today = <Booking>[];
    final byDay = <IstDate, List<Booking>>{};
    for (final b in open) {
      final day = IstDate.fromUtc(b.scheduledStart);
      if (BookingTiming.of(b, now) == BookingTiming.missed) {
        missed.add(b);
      } else if (day.compareTo(todayDate) <= 0) {
        // Includes a slot that began before midnight and is still running.
        today.add(b);
      } else {
        (byDay[day] ??= []).add(b);
      }
    }

    final days = byDay.keys.toList()..sort();
    return BookingAgenda._(
      missed: missed,
      today: today,
      upcoming: [
        for (final day in days)
          BookingSection(
            label: bookingDayLabel(day, todayDate),
            bookings: byDay[day]!,
          ),
      ],
      nextToday: today.where((b) => b.scheduledStart.isAfter(now)).firstOrNull,
    );
  }

  /// Slots that have passed without a check-in, oldest first.
  final List<Booking> missed;

  /// Today's bookings that still hold their slot, including late ones.
  final List<Booking> today;

  /// Tomorrow onwards, one section per day.
  final List<BookingSection> upcoming;

  /// The next booking still to start today, if any.
  final Booking? nextToday;

  bool get isEmpty => missed.isEmpty && today.isEmpty && upcoming.isEmpty;

  /// Needs attention, Today, then one section per later day. Empty groups are
  /// left out.
  List<BookingSection> get sections => [
    if (missed.isNotEmpty)
      BookingSection(
        label: 'Needs attention',
        bookings: missed,
        needsAttention: true,
      ),
    if (today.isNotEmpty) BookingSection(label: 'Today', bookings: today),
    ...upcoming,
  ];
}
