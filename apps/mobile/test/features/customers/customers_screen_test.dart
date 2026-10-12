import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await seededMemoryDb();
    await LocalCustomerRepository(db).create(name: 'Priya', phone: '9001112223');
  });
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Members (under More) lists a customer and opens the profile',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: testOverrides(db), child: const ArenaOpsApp()),
    );
    await settle(tester);

    // Customers live under the More tab as "Members" after the design re-skin.
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Members'));
    await settle(tester);

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);

    await tester.tap(find.text('Priya'));
    await settle(tester);

    // Profile opened: the derived-stats grid is rendered (top of the page).
    expect(find.text('Visits'), findsOneWidget);
    expect(find.text('Total spent'), findsOneWidget);

    // Tear down the tree so drift's stream-close timer is flushed.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
