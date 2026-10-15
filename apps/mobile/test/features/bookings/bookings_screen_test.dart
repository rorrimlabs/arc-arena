/// The Bookings tab: open reservations by business day, each card telling who,
/// when, what and where correctly, whether it is about to start, late or
/// missed, and offering a check-in only on its day. Phone and desktop sizes.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_card.dart';
import 'package:arena_ops/features/bookings/presentation/bookings_screen.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

/// Takes money only: may look at bookings, may not make them.
class _TillAuth extends AuthController {
  @override
  AppUser? build() =>
      const AppUser(id: 'u3', name: 'Till', perms: {Permission.bill});
}

void main() {
  late AppDatabase db;

  // Thursday 15 Oct 2026, 6 PM IST.
  final now = ist(2026, 10, 15, 18, 0);

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Widget app({AuthController Function()? auth}) => ProviderScope(
    overrides: testOverrides(db, clock: FakeClock(now), auth: auth),
    child: const ArenaOpsApp(),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532); // 390 x 844
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(2560, 1600); // 1280 x 800
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> openBookings(
    WidgetTester tester, {
    AuthController Function()? auth,
  }) async {
    await tester.pumpWidget(app(auth: auth));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Bookings'),
      ),
    );
    await settle(tester);
  }

  /// Scrolls the Bookings list down until [finder] is on screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BookingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
  }

  Finder cardOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(BookingCard));

  Finder checkInOn(String name) =>
      find.descendant(of: cardOf(name), matching: find.text('Check in'));

  Future<void> seedBookings() async {
    final clock = FakeClock(now);
    final repo = LocalBookingRepository(db, clock);
    final kabir = await LocalCustomerRepository(
      db,
      clock,
    ).create(name: 'Kabir', phone: '90000 11111');

    Future<void> add({
      String? customerId,
      String? partyName,
      String? phone,
      String activityCode = 'PS5',
      String? gameId,
      String? resourceId,
      required DateTime start,
      Duration length = const Duration(hours: 1),
      int? players,
      String? notes,
      BookingStatus status = BookingStatus.booked,
    }) => repo.create(
      Booking(
        id: '',
        customerId: customerId,
        partyName: partyName,
        phone: phone,
        activityCode: activityCode,
        gameId: gameId,
        resourceId: resourceId,
        scheduledStart: start,
        scheduledEnd: start.add(length),
        playersRequired: players,
        notes: notes,
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 3–4 PM today, never checked in: missed. Named from the customer.
    await add(
      customerId: kabir.id,
      resourceId: 'hex',
      start: ist(2026, 10, 15, 15, 0),
    );
    // 5:30 PM, started without a check-in: late. The party name and phone on
    // the booking win over the customer's.
    await add(
      customerId: kabir.id,
      partyName: '  Riya party ',
      phone: '98470 12345',
      gameId: 'g_eafc',
      resourceId: 'void',
      players: 2,
      start: ist(2026, 10, 15, 17, 30),
    );
    // 6:25 PM on any system, nobody named: a guest, about to start.
    await add(
      start: ist(2026, 10, 15, 18, 25),
      length: const Duration(minutes: 90),
      notes: 'Birthday cake at 7',
    );
    // Tomorrow, on a station that has since been removed.
    await add(
      partyName: 'Tomorrow crew',
      resourceId: 'gone',
      start: ist(2026, 10, 16, 19, 0),
    );
    // Saturday on the pool table.
    await add(
      partyName: 'Weekend squad',
      activityCode: 'POOL',
      resourceId: 'pool1',
      start: ist(2026, 10, 17, 20, 0),
      length: const Duration(hours: 2),
    );
    // Not open any more: never listed.
    await add(
      partyName: 'Already here',
      resourceId: 'ghost',
      start: ist(2026, 10, 15, 17, 0),
      status: BookingStatus.checkedIn,
    );
    await add(
      partyName: 'Called off',
      resourceId: 'rift',
      start: ist(2026, 10, 15, 20, 0),
      status: BookingStatus.cancelled,
    );
  }

  for (final (size, setSize) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('bookings are grouped by day with correct details ($size)', (
      tester,
    ) async {
      setSize(tester);
      await seedBookings();
      await openBookings(tester);

      expect(
        find.text('Bookings'),
        findsNWidgets(2),
        reason: 'screen title and nav label',
      );
      expect(
        find.text('2 today', findRichText: true),
        findsOneWidget,
        reason: 'the late and the upcoming one; the missed one is apart',
      );
      expect(find.text('Next at 6:25 PM'), findsOneWidget);

      // Needs attention: the missed slot, named from its customer.
      await scrollTo(tester, find.text('NEEDS ATTENTION'));
      expect(find.text('1 missed'), findsOneWidget);
      await scrollTo(tester, find.text('Missed · mark no-show or cancel it'));
      expect(find.text('Kabir'), findsOneWidget);
      expect(
        find.text('90000 11111'),
        findsOneWidget,
        reason: "the customer's phone when the booking has none",
      );
      expect(find.text('3:00 PM–4:00 PM · 1h'), findsOneWidget);
      expect(find.text('PlayStation 5 · HEX'), findsOneWidget);

      // Today: the late party, then the guest about to start.
      await scrollTo(tester, find.text('TODAY'));
      expect(find.text('2 bookings'), findsOneWidget);
      await scrollTo(tester, find.text('Late · not checked in'));
      expect(find.text('Riya party'), findsOneWidget);
      expect(find.text('98470 12345'), findsOneWidget);
      expect(find.text('5:30 PM–6:30 PM · 1h'), findsOneWidget);
      expect(
        find.text('PlayStation 5 · EA SPORTS FC 25 · VOID · 2 players'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Starts in 25 min'));
      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('6:25 PM–7:55 PM · 1h 30m'), findsOneWidget);
      expect(find.text('PlayStation 5 · Any system'), findsOneWidget);
      expect(find.text('Birthday cake at 7'), findsOneWidget);

      // Later days, never the raw id of a removed station.
      await scrollTo(tester, find.text('TOMORROW'));
      await scrollTo(tester, find.text('Tomorrow crew'));
      expect(find.text('7:00 PM–8:00 PM · 1h'), findsOneWidget);
      expect(find.text('PlayStation 5 · Station removed'), findsOneWidget);
      expect(find.textContaining('gone'), findsNothing);
      await scrollTo(tester, find.text('SAT 17 OCT'));
      await scrollTo(tester, find.text('Weekend squad'));
      expect(find.text('8:00 PM–10:00 PM · 2h'), findsOneWidget);
      expect(find.text('Pool · Pool Table 1'), findsOneWidget);

      expect(find.text('Already here'), findsNothing);
      expect(find.text('Called off'), findsNothing);
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });

    testWidgets('only today\'s (or an earlier day\'s) bookings offer Check in '
        '($size)', (tester) async {
      setSize(tester);
      await seedBookings();
      await openBookings(tester);

      await scrollTo(tester, find.text('Kabir'));
      expect(
        checkInOn('Kabir'),
        findsOneWidget,
        reason: 'missed: still seatable',
      );
      await scrollTo(tester, find.text('Riya party'));
      expect(checkInOn('Riya party'), findsOneWidget, reason: 'late');
      await scrollTo(tester, find.text('Guest'));
      expect(checkInOn('Guest'), findsOneWidget);
      // Checking in starts a session now, so a later day has no button.
      await scrollTo(tester, find.text('Tomorrow crew'));
      expect(checkInOn('Tomorrow crew'), findsNothing);
      await scrollTo(tester, find.text('Weekend squad'));
      expect(checkInOn('Weekend squad'), findsNothing);
      expect(
        find.descendant(
          of: cardOf('Weekend squad'),
          matching: find.byTooltip('Booking actions'),
        ),
        findsOneWidget,
        reason: 'it can still be edited or cancelled',
      );

      await disposeApp(tester);
    });

    testWidgets('New Booking opens the booking form ($size)', (tester) async {
      setSize(tester);
      await openBookings(tester, auth: TestStaffAuth.new);

      expect(find.text('No bookings yet'), findsOneWidget);
      expect(find.text('0 today', findRichText: true), findsOneWidget);
      expect(find.text('No more today'), findsOneWidget);

      await tester.tap(find.text('New Booking'));
      await settle(tester);

      expect(find.text('New booking'), findsOneWidget);
      expect(find.text('Select customer'), findsOneWidget);

      await disposeApp(tester);
    });
  }

  testWidgets('no New Booking for someone who may not book', (tester) async {
    phone(tester);
    await seedBookings();
    await openBookings(tester, auth: _TillAuth.new);

    expect(find.text('New Booking'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    // They still see what is booked.
    await scrollTo(tester, find.text('Riya party'));
    expect(find.text('Riya party'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a booking for another day shows its day where lists are not '
      'grouped by day', (tester) async {
    // The owner's Today glance lists the same cards in start order.
    desktop(tester);
    tester.view.physicalSize = const Size(2560, 6000);
    await seedBookings();
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Tomorrow · 7:00 PM–8:00 PM · 1h'), findsOneWidget);
    expect(find.text('Sat 17 Oct · 8:00 PM–10:00 PM · 2h'), findsOneWidget);
    expect(
      find.text('5:30 PM–6:30 PM · 1h'),
      findsOneWidget,
      reason: 'today\'s need no day',
    );

    await disposeApp(tester);
  });
}
