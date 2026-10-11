import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/mappers.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class LocalBookingRepository implements BookingRepository {
  LocalBookingRepository(this._db,
      [this._clock = const SystemClock(), this._sync]);

  final AppDatabase _db;
  final Clock _clock;

  /// Cloud mode only (see SyncRecorder). Null in local-only mode.
  final SyncRecorder? _sync;

  /// A booking as the server's booking ops expect it. The device-local reminder
  /// state is sent only on create (each device schedules its own reminders).
  static Map<String, Object?> _wire(BookingRow r) => {
        'id': r.id,
        'customer_id': r.customerId,
        'activity_code': r.activityCode,
        'game_id': r.gameId,
        'resource_id': r.resourceId,
        'scheduled_start': Wire.at(r.scheduledStart),
        'scheduled_end': Wire.at(r.scheduledEnd),
        'players_required': r.playersRequired,
        'controller_requirement': r.controllerRequirement,
        'party_name': r.partyName,
        'phone': r.phone,
        'notes': r.notes,
      };
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
    await _db.transaction(() async {
      await _db.into(_db.bookings).insert(row);
      await _sync?.record(
        kind: 'booking.create',
        entityType: 'booking',
        entityId: row.id,
        payload: {
          ..._wire(row),
          'reminder_status': row.reminderStatus,
          'created_at': Wire.at(row.createdAt),
        },
      );
    });
    return bookingFromRow(row);
  }

  @override
  Future<Booking> update(Booking booking) async {
    final now = _clock.now();
    await _db.transaction(() async {
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
      final sync = _sync;
      if (sync == null) return;
      final row = await (_db.select(_db.bookings)
            ..where((t) => t.id.equals(booking.id)))
          .getSingle();
      await sync.record(
        kind: 'booking.update',
        entityType: 'booking',
        entityId: booking.id,
        payload: {
          ..._wire(row),
          'base_version': await sync.baseVersion('bookings', booking.id),
        },
      );
    });
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
    await _db.transaction(() async {
      await (_db.update(_db.bookings)..where((t) => t.id.equals(id))).write(
        BookingsCompanion(status: Value(status.code), updatedAt: Value(_clock.now())),
      );
      // Check-in only ever happens inside a session start (which carries it);
      // cancel / no-show travel on their own.
      if (status == BookingStatus.cancelled || status == BookingStatus.noShow) {
        await _sync?.record(
          kind: 'booking.set_status',
          entityType: 'booking',
          entityId: id,
          payload: {'id': id, 'status': status.code},
        );
      }
    });
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
