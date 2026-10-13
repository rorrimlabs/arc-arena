/// Bookings are floor work: creating, amending, cancelling and checking in all
/// need `start` (the server's booking.create / update / set_status and session
/// start apply the same rule). These go through [BookingActions] directly —
/// the question is whether the action refuses, not whether a button hides.
///
/// Also: the repository re-checks the slot inside its write transaction, so a
/// booking that loses a race with another booking or a session is refused
/// rather than double-booking the station.
library;

import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pricing_fixtures.dart';

/// A booking repository whose conflict read is stale — it sees no other
/// bookings — standing in for "another booking landed after the action looked".
/// Every write still goes to the real repository.
class _StaleReads implements BookingRepository {
  _StaleReads(this.inner);
  final BookingRepository inner;

  @override
  Future<List<Booking>> overlapping(DateTime fromUtc, DateTime toUtc) async =>
      const [];
  @override
  Stream<List<Booking>> watchUpcoming() => inner.watchUpcoming();
  @override
  Future<List<Booking>> upcoming() => inner.upcoming();
  @override
  Future<Booking?> getById(String id) => inner.getById(id);
  @override
  Future<Booking> create(Booking booking) => inner.create(booking);
  @override
  Future<Booking> update(Booking booking) => inner.update(booking);
  @override
  Future<void> setReminderStatus(String id, ReminderStatus status) =>
      inner.setReminderStatus(id, status);
  @override
  Future<void> setStatus(String id, BookingStatus status) =>
      inner.setStatus(id, status);
}

void main() {
  late AppDatabase db;
  late LocalBookingRepository bookingsRepo;
  late LocalSessionRepository sessionsRepo;
  late LocalCatalogRepository catalog;
  late FakeClock clock;
  late String customerId;

  /// Runs the floor: may book.
  const floor = AppUser(
    id: 'floor',
    name: 'Priya Nair',
    perms: {Permission.start, Permission.bill},
  );

  /// Takes money only: must not book, amend, cancel or check in.
  const till = AppUser(id: 'till', name: 'Sam', perms: {Permission.bill});

  BookingActions actionsFor(AppUser? user, {BookingRepository? bookings}) =>
      BookingActions(
        bookings: bookings ?? bookingsRepo,
        sessions: sessionsRepo,
        catalog: catalog,
        clock: clock,
        guard: PermissionGuard(user),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    clock = FakeClock(ist(2026, 10, 2, 14, 0));
    bookingsRepo = LocalBookingRepository(db, clock);
    sessionsRepo = LocalSessionRepository(db, clock);
    catalog = LocalCatalogRepository(db);
    customerId = (await LocalCustomerRepository(
      db,
      clock,
    ).create(name: 'Rahul')).id;
  });

  tearDown(() async => db.close());

  BookingDraft draft({String? resourceId = 'void', String? editingId}) =>
      BookingDraft(
        customerId: customerId,
        activityCode: 'PS5',
        date: fridayDate,
        startMinuteOfDay: 19 * 60, // 7:00 PM
        durationMinutes: 60,
        gameId: 'g_eafc',
        resourceId: resourceId,
        controllerRequirement: 2,
        editingId: editingId,
      );

  Future<Booking> booked() async {
    final r = await actionsFor(floor).createBooking(draft());
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  group('creating a booking', () {
    test('someone with start can', () async {
      final r = await actionsFor(floor).createBooking(draft());
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect(await bookingsRepo.upcoming(), hasLength(1));
    });

    test('someone without start is refused and nothing is written', () async {
      final r = await actionsFor(till).createBooking(draft());
      expect(r.failureOrNull?.code, 'not_permitted');
      expect(r.failureOrNull!.message, contains('Sam'));
      expect(await bookingsRepo.upcoming(), isEmpty);
    });

    test('nobody signed in is refused', () async {
      final r = await actionsFor(null).createBooking(draft());
      expect(r.failureOrNull?.code, 'not_signed_in');
      expect(await bookingsRepo.upcoming(), isEmpty);
    });

    test('a turned-off account is refused even holding start', () async {
      final r = await actionsFor(
        const AppUser(
          id: 'x',
          name: 'Ex-staff',
          perms: {Permission.start},
          active: false,
        ),
      ).createBooking(draft());
      expect(r.failureOrNull?.code, 'account_inactive');
    });
  });

  group('amending a booking', () {
    test('someone with start can move it', () async {
      final b = await booked();
      final r = await actionsFor(floor)
          .updateBooking(draft(resourceId: 'hex', editingId: b.id));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect((await bookingsRepo.getById(b.id))!.resourceId, 'hex');
    });

    test(
      'someone without start is refused; the booking is unchanged',
      () async {
        final b = await booked();
        final r = await actionsFor(till)
            .updateBooking(draft(resourceId: 'hex', editingId: b.id));
        expect(r.failureOrNull?.code, 'not_permitted');
        expect((await bookingsRepo.getById(b.id))!.resourceId, 'void');
      },
    );
  });

  group('cancelling a booking', () {
    test('someone with start can', () async {
      final b = await booked();
      final r = await actionsFor(floor).cancel(b.id);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect(
        (await bookingsRepo.getById(b.id))!.status,
        BookingStatus.cancelled,
      );
    });

    test(
      'someone without start is refused; the booking stays booked',
      () async {
        final b = await booked();
        final r = await actionsFor(till).cancel(b.id);
        expect(r.failureOrNull?.code, 'not_permitted');
        final after = (await bookingsRepo.getById(b.id))!;
        expect(after.status, BookingStatus.booked);
        expect(after.reminderStatus, isNot(ReminderStatus.done));
      },
    );
  });

  group('checking in', () {
    test(
      'someone with start can: a session starts on the booked system',
      () async {
        final b = await booked();
        clock.set(ist(2026, 10, 2, 19, 5));
        final r = await actionsFor(floor).checkIn(b);
        expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
        expect((await sessionsRepo.openSegments()).single.resourceId, 'void');
        expect(
          (await bookingsRepo.getById(b.id))!.status,
          BookingStatus.checkedIn,
        );
      },
    );

    test(
      'someone without start is refused: no session, still booked',
      () async {
        final b = await booked();
        clock.set(ist(2026, 10, 2, 19, 5));
        final r = await actionsFor(till).checkIn(b);
        expect(r.failureOrNull?.code, 'not_permitted');
        expect(await sessionsRepo.openSegments(), isEmpty);
        expect(
          (await bookingsRepo.getById(b.id))!.status,
          BookingStatus.booked,
        );
      },
    );
  });

  group('the slot is re-checked inside the write', () {
    test(
      'a booking that lost the race is refused, not double-booked',
      () async {
        await booked(); // VOID, 7–8 PM
        // This caller's availability read is stale: it sees VOID as free.
        final racer = actionsFor(floor, bookings: _StaleReads(bookingsRepo));
        final r = await racer.createBooking(draft());
        expect(r.failureOrNull?.code, 'occupied');
        expect(r.failureOrNull!.message, contains('VOID'));
        expect(
          await bookingsRepo.upcoming(),
          hasLength(1),
          reason: 'the second booking must not be written',
        );
      },
    );

    test(
      'an amendment onto a taken slot is refused by the repository too',
      () async {
        await booked(); // VOID
        final other = (await actionsFor(
          floor,
        ).createBooking(draft(resourceId: 'hex'))).valueOrNull!;
        final racer = actionsFor(floor, bookings: _StaleReads(bookingsRepo));
        final r = await racer.updateBooking(
          draft(resourceId: 'void', editingId: other.id),
        );
        expect(r.failureOrNull?.code, 'occupied');
        expect((await bookingsRepo.getById(other.id))!.resourceId, 'hex');
      },
    );
  });

  group('LocalBookingRepository conflict re-check', () {
    Booking at(
      String? resourceId,
      DateTime from,
      Duration length, {
      String id = '',
      BookingStatus status = BookingStatus.booked,
    }) => Booking(
      id: id,
      activityCode: 'PS5',
      resourceId: resourceId,
      scheduledStart: from,
      scheduledEnd: from.add(length),
      status: status,
      partyName: 'Party',
      createdAt: clock.now(),
      updatedAt: clock.now(),
    );
    final seven = ist(2026, 10, 2, 19, 0);
    const hour = Duration(hours: 1);

    test(
      'an overlapping booking on the same station throws BookingConflict',
      () async {
        await bookingsRepo.create(at('void', seven, hour));
        await expectLater(
          bookingsRepo.create(
            at('void', seven.add(const Duration(minutes: 30)), hour),
          ),
          throwsA(
            isA<BookingConflict>().having(
              (e) => e.failure.code,
              'code',
              'occupied',
            ),
          ),
        );
        expect(await bookingsRepo.upcoming(), hasLength(1));
      },
    );

    test(
      'back-to-back, other stations and any-system bookings are fine',
      () async {
        await bookingsRepo.create(at('void', seven, hour));
        await bookingsRepo.create(at('void', seven.add(hour), hour));
        await bookingsRepo.create(at('hex', seven, hour));
        await bookingsRepo.create(at(null, seven, hour));
        expect(await bookingsRepo.upcoming(), hasLength(4));
      },
    );

    test('a cancelled booking does not hold the slot', () async {
      final first = await bookingsRepo.create(at('void', seven, hour));
      await bookingsRepo.setStatus(first.id, BookingStatus.cancelled);
      await bookingsRepo.create(at('void', seven, hour));
      expect(await bookingsRepo.upcoming(), hasLength(1));
    });

    test('updating a booking never conflicts with itself', () async {
      final b = await bookingsRepo.create(at('void', seven, hour));
      final moved = await bookingsRepo.update(
        b.copyWith(scheduledEnd: seven.add(const Duration(minutes: 90))),
      );
      expect(moved.scheduledEnd, seven.add(const Duration(minutes: 90)));
    });

    test(
      'a running session on the station holds it until its scheduled end',
      () async {
        final started = await sessionsRepo.start(
          StartSessionCommand(
            customerId: customerId,
            startedAt: clock.now(), // 2 PM
            scheduledEndAt: ist(2026, 10, 2, 19, 30),
            snapshot: await catalog.currentSnapshot(),
            resourceId: 'void',
            resourceName: 'VOID',
            activityCode: 'PS5',
            controllerCount: 1,
          ),
        );
        expect(started.isOk, isTrue, reason: started.failureOrNull?.display);
        await expectLater(
          bookingsRepo.create(at('void', seven, hour)),
          throwsA(isA<BookingConflict>()),
        );
        // After the session's scheduled end the station is free to book.
        await bookingsRepo.create(at('void', ist(2026, 10, 2, 19, 30), hour));
        expect(await bookingsRepo.upcoming(), hasLength(1));
      },
    );
  });
}
