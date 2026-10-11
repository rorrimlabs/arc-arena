import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/value/enums.dart';

abstract interface class BookingRepository {
  /// Open/checked-in bookings, soonest first (spec §22 upcoming area).
  Stream<List<Booking>> watchUpcoming();
  Future<List<Booking>> upcoming();

  Future<Booking?> getById(String id);
  Future<Booking> create(Booking booking);

  /// Edit an existing booking (spec §18 — staff can amend a reservation).
  Future<Booking> update(Booking booking);

  Future<void> setReminderStatus(String id, ReminderStatus status);
  Future<void> setStatus(String id, BookingStatus status);

  /// Open bookings overlapping [fromUtc, toUtc) — used for conflict checks.
  Future<List<Booking>> overlapping(DateTime fromUtc, DateTime toUtc);
}
