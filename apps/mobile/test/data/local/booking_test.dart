import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late BookingActions actions;
  late LocalBookingRepository bookingsRepo;
  late LocalSessionRepository sessionsRepo;
  late FakeClock clock;
  late String customerId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    clock = FakeClock(ist(2026, 10, 2, 14, 0));
    bookingsRepo = LocalBookingRepository(db, clock);
    sessionsRepo = LocalSessionRepository(db, clock);
    actions = BookingActions(
      bookings: bookingsRepo,
      sessions: sessionsRepo,
      catalog: LocalCatalogRepository(db),
      clock: clock,
    );
    customerId = (await LocalCustomerRepository(db, clock).create(name: 'Rahul')).id;
  });

  tearDown(() async => db.close());

  BookingDraft draft({String? resourceId, String? gameId = 'g_eafc', int? players}) =>
      BookingDraft(
        customerId: customerId,
        activityCode: 'PS5',
        date: fridayDate,
        startMinuteOfDay: 19 * 60, // 7:00 PM
        durationMinutes: 60,
        gameId: gameId,
        resourceId: resourceId,
        playersRequired: players,
        controllerRequirement: 2,
      );

  test('specific-system booking succeeds when compatible and free', () async {
    final r = await actions.createBooking(draft(resourceId: 'void'));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    expect(r.valueOrNull!.resourceId, 'void');
    expect(r.valueOrNull!.status, BookingStatus.booked);
  });

  test('specific-system booking rejects an incompatible game (spec §21)', () async {
    // EA FC is not playable on GHOST in the seed.
    final r = await actions.createBooking(draft(resourceId: 'ghost'));
    expect(r.isErr, isTrue);
    expect(r.failureOrNull!.message, contains('not playable on GHOST'));
  });

  test('overlapping specific bookings on the same system conflict (spec §19)', () async {
    await actions.createBooking(draft(resourceId: 'void'));
    final second = await actions.createBooking(draft(resourceId: 'void'));
    expect(second.isErr, isTrue);
    expect(second.failureOrNull!.code, 'occupied');
  });

  test('any-compatible-system booking stores no fixed system (spec §20A)', () async {
    final r = await actions.createBooking(draft());
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    expect(r.valueOrNull!.isAnySystem, isTrue);
  });

  test('check-in starts a session linked to the booking; booking is preserved (§22–§23)',
      () async {
    final booking = (await actions.createBooking(draft(resourceId: 'void'))).valueOrNull!;

    clock.set(ist(2026, 10, 2, 19, 8)); // arrives 7:08 PM
    final checkedIn = await actions.checkIn(booking);
    expect(checkedIn.isOk, isTrue, reason: checkedIn.failureOrNull?.display);

    final session = checkedIn.valueOrNull!;
    expect(session.bookingId, booking.id); // linked
    expect(session.startedAt, ist(2026, 10, 2, 19, 8)); // real start

    // The actual system used is in the segment.
    final segs = await sessionsRepo.segmentsFor(session.id);
    expect(segs.single.resourceId, 'void');

    // The booking stays as the planned record, now checked in.
    final after = await bookingsRepo.getById(booking.id);
    expect(after!.status, BookingStatus.checkedIn);
    expect(after.scheduledStart, ist(2026, 10, 2, 19, 0)); // planned time unchanged
  });
}
