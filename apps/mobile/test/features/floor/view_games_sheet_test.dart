/// The floor's View games sheet: changing a game's status on a station is a
/// Settings job (game.set_compat). Someone without `settings` gets a
/// read-only list — no edit buttons, rows that do not open the editor — and
/// the action refuses them anyway (see test/app/catalog_actions_test.dart).
library;

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/floor/presentation/sheets/view_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  late Resource hex;

  setUp(() async {
    db = await seededMemoryDb();
    hex = (await LocalCatalogRepository(
      db,
    ).resources()).firstWhere((r) => r.id == 'hex');
  });
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> open(WidgetTester tester, {required bool staff}) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(db, auth: staff ? TestStaffAuth.new : null),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showViewGamesSheet(context, hex),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(
      find.textContaining('games playable on this system'),
      findsOneWidget,
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('an owner can change a game status on the station', (
    tester,
  ) async {
    await open(tester, staff: false);
    expect(find.byTooltip('Set status on HEX'), findsWidgets);

    await tester.tap(find.byTooltip('Set status on HEX').first);
    await settle(tester);
    expect(find.text('Status on HEX only'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the editor starts from the stored note, so a status change '
      'keeps it', (tester) async {
    final first = (await tester.runAsync(
      () => LocalCatalogRepository(db).gamesForResource('hex'),
    ))!.first.game;
    await tester.runAsync(() => LocalCatalogRepository(db).setCompatibility(
          first.id,
          'hex',
          GameAvailability.maintenance,
          notes: 'disc scratched',
        ));
    await open(tester, staff: false);
    // The row (unavailable games sort last) says why it is unavailable here.
    await tester.scrollUntilVisible(find.textContaining('disc scratched'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('disc scratched'), findsOneWidget);

    final row = find.ancestor(of: find.text(first.name), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip('Set status on HEX')));
    await settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'disc scratched',
    );
    await close(tester);
  });

  testWidgets('staff without settings see a read-only list', (tester) async {
    await open(tester, staff: true);
    expect(find.byTooltip('Set status on HEX'), findsNothing);
    // The controls guide is still there to read out to the customer.
    expect(find.byTooltip('Controls'), findsWidgets);

    // Tapping a game does not open the status editor.
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);
    expect(find.text('Status on HEX only'), findsNothing);
    await close(tester);
  });
}
