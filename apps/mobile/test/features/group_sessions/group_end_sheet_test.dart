/// Widget-level: the group End & Bill sheet records the total it shows. The
/// end instant is fixed when the sheet opens, so time passing while it stays
/// open (and any rebuild) changes neither the shown nor the recorded bill.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/group_sessions/presentation/sheets/group_end_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  final opened = ist(2026, 10, 2, 19, 0); // Friday, no rule

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('the bill shown when the sheet opens is the bill recorded',
      (tester) async {
    tester.view.physicalSize = const Size(1179, 5200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final clock = FakeClock(opened);
    final who = await LocalCustomerRepository(db).create(name: 'Dev');
    final groups = LocalGroupSessionRepository(db, clock);
    final created = await groups.create(CreateGroupCommand(
      primaryCustomerId: who.id,
      playerCount: 1,
      purchasedControllerCount: 1,
      startedAt: opened.subtract(const Duration(hours: 1)),
      scheduledEndAt: opened.add(const Duration(hours: 1)),
      snapshot: await LocalCatalogRepository(db).currentSnapshot(),
      billingMode: GroupBillingMode.perSystem,
      assignments: const [
        GroupAssignmentDraft(
          playerNumber: 1,
          resourceId: 'hex',
          resourceName: 'HEX',
          activityCode: 'PS5',
          controllerCount: 1,
        ),
      ],
    ));
    expect(created.isOk, isTrue, reason: created.failureOrNull?.display);
    final id = created.valueOrNull!.id;
    final active = (await groups.activeGroups()).single;

    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(db, clock: clock),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGroupEndSheet(context, active),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    // One hour at 1 controller (seeded ₹150/h).
    final shown = const Paise(15000).display;
    expect(find.text(shown), findsOneWidget);

    // Staff leave the sheet open for 10 minutes and the sheet rebuilds.
    clock.advance(const Duration(minutes: 10));
    await tester.tap(find.text('Mark complimentary (waive)'));
    await settle(tester);
    await tester.tap(find.text('Mark complimentary (waive)'));
    await settle(tester);
    expect(find.text(shown), findsOneWidget, reason: 'the shown total is fixed');

    await tester.tap(find.text('End & bill'));
    await settle(tester);

    final ended = (await groups.getById(id))!;
    expect(ended.status, GroupSessionStatus.completed);
    expect(ended.billedAmountPaise, 15000, reason: 'recorded = shown');
    expect(ended.actualEndedAt, opened);

    await tester.pump(const Duration(seconds: 7)); // let the toast close
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
