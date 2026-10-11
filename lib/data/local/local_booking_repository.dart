import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/mappers.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class LocalBookingRepository implements BookingRepository {
  LocalBookingRepository(this._db, [this._clock = const SystemClock()]);

  final AppDatabase _db;
  final Clock _clock;
  static const _uuid = Uuid();

  SimpleSelectStatement<$BookingsTable, BookingRow> _upcomingQuery() =>
      _db.select(_db.bookings)
        ..where((t) => t.status.isIn([
              BookingStatus.booked.code,
              BookingStatus.checkedIn.code,
            ]))
        ..orderBy([(t) => OrderingTerm(expression: t.scheduledStart)]);

  @override
  Stream<List<Booking>> watchUpcoming() =>
      _upcomingQuery().watch().map((r) => r.map(bookingFromRow).toList());

  @override
  Future<List<Booking>> upcoming() async =>
      (await _upcomingQuery().get()).map(bookingFromRow).toList();

  @override
  Future<Booking?> getById(String id) async {
    final row = await (_db.select(_db.bookings)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : bookingFromRow(row);
  }

  @override
  Future<Booking> create(Booking booking) async {
    final now = _clock.now();
    final row = BookingRow(
      id: booking.id.isEmpty ? _uuid.v4() : booking.id,
      customerId: booking.customerId,
      activityCode: booking.activityCode,
      gameId: booking.gameId,
      resourceId: booking.resourceId,
      scheduledStart: booking.scheduledStart.toUtc(),
      scheduledEnd: booking.scheduledEnd.toUtc(),
      playersRequired: booking.playersRequired,
      controllerRequirement: booking.controllerRequirement,
      status: booking.status.code,
      partyName: booking.partyName,
      phone: booking.phone,
      notes: booking.notes,
      reminderStatus: booking.reminderStatus.code,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.bookings).insert(row);
    return bookingFromRow(row);
  }

  @override
  Future<Booking> update(Booking booking) async {
    final now = _clock.now();
    await (_db.update(_db.bookings)..where((t) => t.id.equals(booking.id)))
        .write(BookingsCompanion(
      customerId: Value(booking.customerId),
      activityCode: Value(booking.activityCode),
      gameId: Value(booking.gameId),
      resourceId: Value(booking.resourceId),
      scheduledStart: Value(booking.scheduledStart.toUtc()),
      scheduledEnd: Value(booking.scheduledEnd.toUtc()),
      playersRequired: Value(booking.playersRequired),
      controllerRequirement: Value(booking.controllerRequirement),
      status: Value(booking.status.code),
      partyName: Value(booking.partyName),
      phone: Value(booking.phone),
      notes: Value(booking.notes),
      reminderStatus: Value(booking.reminderStatus.code),
      updatedAt: Value(now),
    ));
    return (await getById(booking.id))!;
  }

  @override
  Future<void> setReminderStatus(String id, ReminderStatus status) async {
    await (_db.update(_db.bookings)..where((t) => t.id.equals(id))).write(
      BookingsCompanion(
        reminderStatus: Value(status.code),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  @override
  Future<void> setStatus(String id, BookingStatus status) async {
    await (_db.update(_db.bookings)..where((t) => t.id.equals(id))).write(
      BookingsCompanion(status: Value(status.code), updatedAt: Value(_clock.now())),
    );
  }

  @override
  Future<List<Booking>> overlapping(DateTime fromUtc, DateTime toUtc) async {
    // Half-open overlap: start < to AND end > from.
    final rows = await (_db.select(_db.bookings)
          ..where((t) =>
              t.status.equals(BookingStatus.booked.code) &
              t.scheduledStart.isSmallerThanValue(toUtc) &
              t.scheduledEnd.isBiggerThanValue(fromUtc)))
        .get();
    return rows.map(bookingFromRow).toList();
  }
}
