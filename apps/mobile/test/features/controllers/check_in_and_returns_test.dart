/// Widget-level: booking check-in with physical pads (including a borrow), the
/// group change-controllers sheet catching the game's local-player limit
/// before Apply, and returning a borrowed pad from the end sheet.
library;

import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_controller_allocation_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/check_in_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_assign_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  final now = ist(2026, 10, 2, 19, 2); // standard band; the party arrives

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> disposeApp(WidgetTester tester) async {
    // Let any toast (3 s, or 6 s for an error) time out first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1179, 5200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget opener(void Function(BuildContext) open) => ProviderScope(
        overrides: testOverrides(db, clock: FakeClock(now)),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<Set<String>> held() async => {
        for (final a
            in await LocalControllerAllocationRepository(db).openPadAllocations())
          a.controllerId,
      };

  FilledButton button(WidgetTester tester, String key) =>
      tester.widget<FilledButton>(find.byKey(ValueKey(key)));

  testWidgets('check-in: 4 booked at VOID — blocked until 2 are borrowed, '
      'then the session starts with all 4', (tester) async {
    phone(tester);
    final clock = FakeClock(ist(2026, 10, 2, 14, 0));
    final who = await LocalCustomerRepository(db).create(name: 'Rahul');
    final booking = (await BookingActions(
      bookings: LocalBookingRepository(db, clock),
      sessions: LocalSessionRepository(db, clock),
      catalog: LocalCatalogRepository(db),
      clock: clock,
      guard: const PermissionGuard(AppUser(
        id: 'u2',
        name: 'Staff',
        perms: {Permission.start},
      )),
    ).createBooking(BookingDraft(
      customerId: who.id,
      activityCode: 'PS5',
      date: fridayDate,
      startMinuteOfDay: 19 * 60,
      durationMinutes: 60,
      gameId: 'g_eafc',
      resourceId: 'void',
      controllerRequirement: 4,
    )))
        .valueOrNull!;

    await tester.pumpWidget(opener((c) => showCheckInSheet(c, booking)));
    await tester.tap(find.text('open'));
    await settle(tester);

    // No party name on the booking: the customer's name is shown, never "null".
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('check-in-title'))).data,
        'Check in · Rahul');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('check-in-station'))).data,
        'VOID · booked for 4 controllers');
    expect(find.byKey(const ValueKey('pad-shortfall')), findsOneWidget);
    expect(button(tester, 'check-in-confirm').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('pad-ctl_hex_1')));
    await settle(tester);
    expect(button(tester, 'check-in-confirm').onPressed, isNull,
        reason: 'still one short');
    await tester.tap(find.byKey(const ValueKey('pad-ctl_hex_2')));
    await settle(tester);
    expect(button(tester, 'check-in-confirm').onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('check-in-confirm')));
    await settle(tester);
    expect(await held(),
        {'ctl_void_1', 'ctl_void_2', 'ctl_hex_1', 'ctl_hex_2'});
    final b = await LocalBookingRepository(db).getById(booking.id);
    expect(b!.status, BookingStatus.checkedIn);
    await disposeApp(tester);
  });

  testWidgets('group change-controllers: a third Tekken controller on a '
      'shared station is shown and Apply stays disabled', (tester) async {
    phone(tester);
    final who = await LocalCustomerRepository(db).create(name: 'Rahul');
    final groups = LocalGroupSessionRepository(db);
    final created = await groups.create(CreateGroupCommand(
      primaryCustomerId: who.id,
      playerCount: 2,
      purchasedControllerCount: 2,
      startedAt: now,
      scheduledEndAt: now.add(const Duration(hours: 1)),
      snapshot: await LocalCatalogRepository(db).currentSnapshot(),
      billingMode: GroupBillingMode.perSystem,
      assignments: const [
        GroupAssignmentDraft(
            playerNumber: 1,
            resourceId: 'hex',
            resourceName: 'HEX',
            activityCode: 'PS5',
            gameId: 'g_tekken8',
            controllerIds: ['ctl_hex_1']),
        GroupAssignmentDraft(
            playerNumber: 2,
            resourceId: 'hex',
            resourceName: 'HEX',
            activityCode: 'PS5',
            gameId: 'g_tekken8',
            controllerIds: ['ctl_hex_2']),
      ],
    ));
    expect(created.isOk, isTrue, reason: created.failureOrNull?.display);
    final g = (await groups.activeGroups()).single;

    await tester.pumpWidget(opener((c) => showGroupChangeControllersSheet(c,
        group: g, current: g.currentForPlayer(1)!)));
    await tester.tap(find.text('open'));
    await settle(tester);

    // HEX-2 is Player 2's; ask for 2 and borrow one from VOID.
    await tester.tap(find.byKey(const ValueKey('ctl-count-2')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pad-ctl_void_1')));
    await settle(tester);

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('assign-problem'))).data,
        contains('Tekken 8 supports 2 local players — 3 controllers on HEX.'));
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull);
    expect(await held(), {'ctl_hex_1', 'ctl_hex_2'}, reason: 'nothing saved');
    await disposeApp(tester);
  });

  testWidgets('end sheet: tick a borrowed pad and it is returned home once '
      'the session ends', (tester) async {
    phone(tester);
    final who = await LocalCustomerRepository(db).create(name: 'Kabir');
    final sessions = LocalSessionRepository(db);
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: now,
      scheduledEndAt: now.add(const Duration(hours: 1)),
      snapshot: await LocalCatalogRepository(db).currentSnapshot(),
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      controllerCount: 1,
      controllerIds: const ['ctl_hex_1'],
      borrowControllerIds: const ['ctl_hex_1'],
    ));
    expect(started.isOk, isTrue);
    final active = (await sessions.active()).single;

    await tester.pumpWidget(opener((c) => showEndSessionSheet(c, active)));
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.text('HEX-1 → returned to HEX'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('return-ctl_hex_1')));
    await settle(tester);
    await tester.tap(find.text('End & record'));
    await settle(tester);

    final pad = (await LocalCatalogRepository(db).controllers())
        .firstWhere((c) => c.id == 'ctl_hex_1');
    expect(pad.currentResourceId, 'hex');
    expect(pad.loanSessionRef, isNull);
    final moves =
        await LocalControllerAllocationRepository(db).movesForController(pad.id);
    expect(moves.map((m) => '${m.fromResourceId}->${m.toResourceId}'),
        ['hex->void', 'void->hex']);
    expect(await held(), isEmpty);
    await disposeApp(tester);
  });
}
