import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  // testOverrides already overrides nowProvider with a static (non-ticking)
  // stream, so pumpAndSettle-free pumping is safe and no periodic timer leaks.
  Widget app({AuthController Function()? auth}) => ProviderScope(
      overrides: testOverrides(db, auth: auth), child: const ArenaOpsApp());

  // Screens show a loading spinner briefly; pumpAndSettle would wait on that
  // animation forever, so pump fixed frames instead.
  Future<void> settleData(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('boots to the Today tab with six navigation destinations',
      (tester) async {
    await tester.pumpWidget(app());
    await settleData(tester);

    // Today · Floor · Bookings · Money · Reports · More.
    expect(find.byType(NavigationDestination), findsNWidgets(6));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Floor'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // Boots to Today (owner glance).
    expect(find.text('Takings today'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('can switch to the Floor tab', (tester) async {
    await tester.pumpWidget(app());
    await settleData(tester);

    await tester.tap(find.text('Floor'));
    await settleData(tester);

    expect(find.text('New Session'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('can switch to the Bookings tab', (tester) async {
    await tester.pumpWidget(app());
    await settleData(tester);

    await tester.tap(find.text('Bookings'));
    await settleData(tester);

    expect(find.text('Bookings'), findsNWidgets(2)); // title + nav label
    expect(find.text('No bookings yet'), findsOneWidget);
    expect(find.text('New Booking'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('staff see Floor, Bookings and More', (tester) async {
    await tester.pumpWidget(app(auth: TestStaffAuth.new));
    await settleData(tester);

    final nav = find.byType(NavigationBar);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    for (final label in ['Floor', 'Bookings', 'More']) {
      expect(find.descendant(of: nav, matching: find.text(label)),
          findsOneWidget);
    }

    await tester.tap(find.descendant(of: nav, matching: find.text('Bookings')));
    await settleData(tester);
    expect(find.text('New Booking'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('can switch to the Reports tab', (tester) async {
    await tester.pumpWidget(app());
    await settleData(tester);

    await tester.tap(find.text('Reports'));
    await settleData(tester);

    // Reports opens on the real report for the selected window. A freshly
    // seeded arena has traded nothing, so it must say so rather than show
    // invented figures.
    expect(find.text('Today'), findsWidgets); // range chips
    expect(find.text('Nothing recorded yet'), findsOneWidget);

    await disposeApp(tester);
  });
}
