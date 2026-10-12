import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

/// Covers the Today header actions (Bookings + Notifications) and the
/// Upcoming-bookings section added to the owner glance.
void main() {
  late AppDatabase db;

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Widget app() =>
      ProviderScope(overrides: testOverrides(db), child: const ArenaOpsApp());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Today shows Bookings + Notifications actions and a bookings section',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.byTooltip('Bookings'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);

    // Upcoming bookings section with its empty state (no bookings seeded). It's
    // below the fold, so scroll the glance list down to it first.
    await tester.scrollUntilVisible(
      find.text('No bookings yet'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No bookings yet'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('Notifications bell opens the reminders screen', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No upcoming reminders'), findsOneWidget);

    await disposeApp(tester);
  });
}
