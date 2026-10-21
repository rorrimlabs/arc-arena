/// Brief §16 #20 — the main staff screens render and work at phone and
/// desktop sizes — and §3 — an occupied card answers, without a tap, who is
/// playing, what, on how many controllers, from when until when, and for how
/// much.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/floor/presentation/floor_screen.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;

  // Friday 6 PM — open.
  final start = ist(2026, 10, 2, 18, 0);

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Widget app(Clock clock) => ProviderScope(
        overrides: testOverrides(db, clock: clock),
        child: const ArenaOpsApp(),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeApp(WidgetTester tester) async {
    // Let any toast (3 s, or 6 s for an error) time out first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A live 2-controller session on HEX for "Kabir", started at 6 PM.
  Future<void> seedSession() async {
    final catalog = LocalCatalogRepository(db);
    final customers = LocalCustomerRepository(db, FakeClock(start));
    final sessions = LocalSessionRepository(db, FakeClock(start));
    final kabir = await customers.create(name: 'Kabir');
    final result = await sessions.start(StartSessionCommand(
      customerId: kabir.id,
      startedAt: start,
      scheduledEndAt: start.add(const Duration(hours: 1)),
      snapshot: await catalog.currentSnapshot(),
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      gameId: 'g_eafc',
      controllerCount: 2,
    ));
    expect(result.isOk, isTrue, reason: result.failureOrNull?.display);
  }

  Future<void> openFloor(WidgetTester tester, Clock clock) async {
    await tester.pumpWidget(app(clock));
    await settle(tester);
    await tester.tap(find.text('Floor'));
    await settle(tester);
  }

  testWidgets('an occupied card shows who, what, when and how much',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await seedSession();
    // 20 minutes in.
    final clock = FakeClock(start.add(const Duration(minutes: 20)));
    await openFloor(tester, clock);

    expect(find.text('HEX'), findsOneWidget);
    expect(find.text('Kabir'), findsOneWidget, reason: 'occupied by whom');
    expect(find.text('EA SPORTS FC 25'), findsWidgets, reason: 'which game');
    expect(find.text('2 ctrl'), findsOneWidget, reason: 'controllers assigned');
    expect(find.text('6:00 PM → 7:00 PM'), findsOneWidget,
        reason: 'started at and due at');
    // 40 minutes left of the hour, shown as a timestamp-derived countdown.
    expect(find.text('40:00'), findsOneWidget);
    // 20 min of ₹280/hr = ₹93.33 → ₹93 at the configured nearest-₹1 rounding.
    expect(find.textContaining('₹93'), findsOneWidget, reason: 'bill so far');

    // Quick actions are present while the session is still comfortable, not
    // only once it is ending.
    expect(find.text('+30'), findsOneWidget);
    expect(find.text('Bill'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a walk-in session starts without registering anyone',
      (tester) async {
    // Brief §16 #1 — a quick guest session, with no registration step.
    tester.view.physicalSize = const Size(1179, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final clock = FakeClock(start);
    await openFloor(tester, clock);

    // Start on a free station.
    await tester.tap(find.text('Start').first);
    await settle(tester);
    // Walk-in, instead of searching for or registering a customer.
    await tester.tap(find.text('Select customer'));
    await settle(tester);
    await tester.tap(find.text('Walk-in — start without details'));
    await settle(tester);
    // How many controllers, then go.
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await settle(tester);
    await tester.tap(find.text('Start session'));
    await settle(tester);

    final sessions = LocalSessionRepository(db);
    final active = await sessions.active();
    expect(active.length, 1, reason: 'the session is persisted, not just drawn');

    final s = active.single;
    expect(s.session.startedAt, start, reason: 'timed from the authoritative clock');
    expect(s.session.scheduledEndAt, start.add(const Duration(hours: 1)));
    expect(s.current.controllerCount, 2);

    // The guest is a real customer row, so the visit is billable and countable,
    // but it never entered the member directory.
    final customers = LocalCustomerRepository(db);
    final guest = await customers.getById(s.session.customerId);
    expect(guest!.isGuest, isTrue);
    expect(guest.displayName, 'Walk-in');
    expect(await customers.search('Walk'), isEmpty,
        reason: 'walk-ins are visits, not members in the directory');

    await disposeApp(tester);
  });

  testWidgets('the floor renders without overflow on a phone', (tester) async {
    // iPhone-class logical size.
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await seedSession();
    await openFloor(tester, FakeClock(start.add(const Duration(minutes: 5))));

    expect(find.text('Kabir'), findsOneWidget);
    expect(find.text('Start'), findsWidgets, reason: 'free stations usable');
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('the floor renders without overflow at desktop width',
      (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await seedSession();
    await openFloor(tester, FakeClock(start.add(const Duration(minutes: 5))));

    expect(find.text('Kabir'), findsOneWidget);
    expect(find.text('Start'), findsWidgets);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('a finished unpaid session appears in Awaiting payment',
      (tester) async {
    // Phone width, but tall enough that the whole floor list is laid out —
    // the queue sits under the station grid.
    tester.view.physicalSize = const Size(1179, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await seedSession();
    final sessions = LocalSessionRepository(db);
    final active = await sessions.active();
    final s = active.single;
    final end = start.add(const Duration(hours: 1));
    await sessions.end(EndSessionCommand(
      sessionId: s.session.id,
      actualEndedAt: end,
      charges: const [],
      billedAmountPaise: 28000,
    ));

    await openFloor(tester, FakeClock(end.add(const Duration(minutes: 1))));

    expect(find.text('AWAITING PAYMENT'), findsOneWidget);
    expect(find.text('Collect'), findsOneWidget);
    // HEX is free again the moment the session ended.
    expect(find.text('Start'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('recording a payment clears the session from the queue',
      (tester) async {
    tester.view.physicalSize = const Size(1179, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await seedSession();
    final sessions = LocalSessionRepository(db);
    final s = (await sessions.active()).single;
    final end = start.add(const Duration(hours: 1));
    await sessions.end(EndSessionCommand(
      sessionId: s.session.id,
      actualEndedAt: end,
      charges: const [],
      billedAmountPaise: 28000,
    ));

    await openFloor(tester, FakeClock(end.add(const Duration(minutes: 1))));
    await tester.tap(find.text('Collect'));
    await settle(tester);

    // The sheet opens prefilled with the outstanding balance.
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.textContaining('Record ₹280'), findsOneWidget);

    await tester.tap(find.textContaining('Record ₹280'));
    await settle(tester);

    final after = await sessions.getById(s.session.id);
    expect(after!.paymentStatus, PaymentStatus.paid);
    expect((await sessions.paymentsFor(s.session.id)).single.amountPaise, 28000);

    await disposeApp(tester);
  });

  testWidgets('bookings live on their own tab; the floor only shows Reserved',
      (tester) async {
    tester.view.physicalSize = const Size(1179, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // HEX is booked from 7 PM; it is 6 PM.
    await LocalBookingRepository(db, FakeClock(start)).create(Booking(
      id: '',
      partyName: 'Riya party',
      activityCode: 'PS5',
      resourceId: 'hex',
      scheduledStart: start.add(const Duration(hours: 1)),
      scheduledEnd: start.add(const Duration(hours: 2)),
      status: BookingStatus.booked,
      createdAt: start,
      updatedAt: start,
    ));
    await openFloor(tester, FakeClock(start));

    final floor = find.byType(FloorScreen);
    expect(
        find.descendant(of: floor, matching: find.byTooltip('Bookings')),
        findsNothing,
        reason: 'no bookings shortcut in the floor header');
    expect(find.text('UPCOMING BOOKINGS'), findsNothing);
    expect(find.text('Riya party'), findsNothing);
    expect(find.text('Check in'), findsNothing);
    // The station it holds still says so.
    expect(find.text('RESERVED'), findsOneWidget);

    await disposeApp(tester);
  });
}
