/// Step 2: the controller inventory is visible and editable where stations are
/// managed. Marking a pad faulty must be a one-screen job for staff, and the
/// shortfall must read back immediately.
library;

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/features/more/presentation/stations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Widget app() => ProviderScope(
    overrides: testOverrides(db),
    child: const MaterialApp(home: StationsScreen()),
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

  testWidgets('each PS5 station reports its usable controllers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);

    // Four PS5 stations, two pads each.
    expect(find.text('2 of 2 controllers usable'), findsNWidgets(4));
    // Pool and the lounge have none, so they say nothing about controllers.
    expect(find.text('Pool Table 1'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a faulty pad shows as a shortfall on the station', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await LocalCatalogRepository(db)
        .setControllerStatus('ctl_hex_2', ControllerStatus.faulty);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('1 of 2 controllers usable'), findsOneWidget);
    expect(find.text('2 of 2 controllers usable'), findsNWidgets(3));

    await disposeApp(tester);
  });

  testWidgets('staff can open a station and mark a controller faulty', (
    tester,
  ) async {
    // A realistic phone: the sheet is scrollable, so it needs no extra height.
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);

    // Open HEX's controller list.
    await tester.tap(find.byTooltip('Controllers').first);
    await settle(tester);

    expect(find.text('HEX controllers'), findsOneWidget);
    expect(find.text('2 of 2 usable'), findsOneWidget);
    expect(find.text('HEX-1'), findsOneWidget);
    expect(find.text('HEX-2'), findsOneWidget);

    // Mark HEX-1 faulty — target that row's own menu, not just the first.
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('HEX-1'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Set status'),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Faulty').last);
    await settle(tester);

    expect(find.text('HEX-1 is faulty'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'left stick drift');
    await tester.tap(find.text('Mark faulty'));
    await settle(tester);

    final stored = (await LocalCatalogRepository(
      db,
    ).controllers()).firstWhere((c) => c.id == 'ctl_hex_1');
    expect(stored.status, ControllerStatus.faulty);
    expect(stored.notes, 'left stick drift');

    // The sheet reflects it without a refetch.
    expect(find.text('1 of 2 usable'), findsOneWidget);

    await disposeApp(tester);
  });

  // ---- Phase A: inventory, move/borrow, RIFT mode ------------------------

  Future<LocalCatalogRepository> openHex(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1179, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.byTooltip('Controllers').first); // HEX
    await settle(tester);
    return LocalCatalogRepository(db);
  }

  Finder manageMenu(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
    matching: find.byTooltip('Manage'),
  );

  testWidgets('owner can add a controller to a station', (tester) async {
    final catalog = await openHex(tester);
    await tester.tap(find.byTooltip('Add controller'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'HEX-3');
    await tester.tap(find.text('Add'));
    await settle(tester);

    final pads = await catalog.controllers();
    final added = pads.where((c) => c.label == 'HEX-3').toList();
    expect(added, hasLength(1));
    expect(added.single.homeResourceId, 'hex');
    expect(added.single.currentResourceId, 'hex');
    expect(find.text('3 of 3 usable'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('owner can rename a controller', (tester) async {
    final catalog = await openHex(tester);
    await tester.tap(manageMenu('HEX-1'));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'HEX-A');
    await tester.tap(find.text('Rename').last);
    await settle(tester);

    final c = (await catalog.controllers()).firstWhere(
      (x) => x.id == 'ctl_hex_1',
    );
    expect(c.label, 'HEX-A');
    await disposeApp(tester);
  });

  testWidgets('owner can set a controller home station (no physical move)', (
    tester,
  ) async {
    final catalog = await openHex(tester);
    await tester.tap(manageMenu('HEX-1'));
    await settle(tester);
    await tester.tap(find.text('Set home station'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-void'))); // station picker
    await settle(tester);

    final c = (await catalog.controllers()).firstWhere(
      (x) => x.id == 'ctl_hex_1',
    );
    expect(c.homeResourceId, 'void', reason: 'home changed');
    expect(c.currentResourceId, 'hex', reason: 'pad did not physically move');
    await disposeApp(tester);
  });

  testWidgets('owner can mark a controller unavailable', (tester) async {
    final catalog = await openHex(tester);
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('HEX-2'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Set status'),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Unavailable').last);
    await settle(tester);

    final c = (await catalog.controllers()).firstWhere(
      (x) => x.id == 'ctl_hex_2',
    );
    expect(c.status, ControllerStatus.unavailable);
    expect(find.text('1 of 2 usable'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('owner can move a controller then return it home', (
    tester,
  ) async {
    final catalog = await openHex(tester);
    await tester.tap(manageMenu('HEX-1'));
    await settle(tester);
    await tester.tap(find.text('Move / borrow'));
    await settle(tester);
    await tester.tap(
      find.widgetWithText(ChoiceChip, 'VOID'),
    ); // destination chip
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await settle(tester);

    var c = (await catalog.controllers()).firstWhere(
      (x) => x.id == 'ctl_hex_1',
    );
    expect(c.currentResourceId, 'void');
    expect(c.loanReturnTo, 'hex');

    // It now shows under "belongs here, currently elsewhere" with a recall.
    await tester.tap(find.text('Return home').first);
    await settle(tester);
    c = (await catalog.controllers()).firstWhere((x) => x.id == 'ctl_hex_1');
    expect(c.currentResourceId, 'hex', reason: 'recalled home');
    expect(c.loanReturnTo, isNull);
    await disposeApp(tester);
  });

  testWidgets('a duplicate controller label is refused', (tester) async {
    final catalog = await openHex(tester);
    await tester.tap(find.byTooltip('Add controller'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'hex-2'); // case-insensitive
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(
      find.text('A controller is already labelled hex-2.'),
      findsOneWidget,
    );
    final pads = await catalog.controllers();
    expect(pads.where((c) => c.homeResourceId == 'hex'), hasLength(2));
    await disposeApp(tester);
  });

  testWidgets('re-homing a loaned pad onto the station it stands at settles '
      'the loan', (tester) async {
    final catalog = await openHex(tester);
    // Loan HEX-1 to VOID.
    await tester.tap(manageMenu('HEX-1'));
    await settle(tester);
    await tester.tap(find.text('Move / borrow'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'VOID'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await settle(tester);
    var c = (await catalog.controllers()).firstWhere(
      (x) => x.id == 'ctl_hex_1',
    );
    expect(c.loanReturnTo, 'hex');
    await disposeApp(tester);

    // From VOID's sheet, make VOID its home.
    tester.view.physicalSize = const Size(1179, 3000);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.byTooltip('Controllers').at(1)); // VOID
    await settle(tester);
    await tester.tap(manageMenu('HEX-1'));
    await settle(tester);
    await tester.tap(find.text('Set home station'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-void')));
    await settle(tester);

    c = (await catalog.controllers()).firstWhere((x) => x.id == 'ctl_hex_1');
    expect(c.homeResourceId, 'void');
    expect(c.currentResourceId, 'void');
    expect(c.loanReturnTo, isNull, reason: 'no longer owes a return');
    await disposeApp(tester);
  });

  testWidgets(
    'RIFT shows a PS5/VR mode selector; a PS5-only station does not',
    (tester) async {
      final catalog = await openHex(tester); // HEX sheet open
      expect(find.widgetWithText(ChoiceChip, 'Either'), findsNothing);
      await disposeApp(tester);

      // Reopen on RIFT (4th Controllers button).
      tester.view.physicalSize = const Size(1179, 3000);
      tester.view.devicePixelRatio = 3.0;
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.tap(find.byTooltip('Controllers').at(3)); // RIFT
      await settle(tester);
      expect(find.widgetWithText(ChoiceChip, 'Either'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'PS5'));
      await settle(tester);
      final rift = (await catalog.resources()).firstWhere(
        (r) => r.id == 'rift',
      );
      expect(rift.currentMode, 'PS5');
      await disposeApp(tester);
    },
  );

  testWidgets('the RIFT mode selector is disabled while RIFT is occupied', (
    tester,
  ) async {
    // An open single segment on RIFT marks it busy.
    await db
        .into(db.sessionSegments)
        .insert(
          SessionSegmentsCompanion.insert(
            id: 'seg-x',
            sessionId: 'sess-x',
            index: 0,
            resourceId: 'rift',
            activityCode: 'PS5',
            startedAt: DateTime.utc(2026, 10, 1, 9),
            createdAt: DateTime.utc(2026, 10, 1, 9),
          ),
        );
    tester.view.physicalSize = const Size(1179, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.byTooltip('Controllers').at(3)); // RIFT
    await settle(tester);

    expect(find.textContaining('End the current session'), findsOneWidget);
    // Tapping a disabled chip is a no-op: mode stays unset.
    await tester.tap(find.widgetWithText(ChoiceChip, 'VR'));
    await settle(tester);
    final rift = (await LocalCatalogRepository(
      db,
    ).resources()).firstWhere((r) => r.id == 'rift');
    expect(rift.currentMode, isNull);
    await disposeApp(tester);
  });
}
