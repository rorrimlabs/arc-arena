/// Date pickers open on the arena's today from the injected clock
/// (clockProvider), never the device's wall clock — so a tablet with a wrong
/// clock (or a test's FakeClock) decides what "today" is.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/more/presentation/holidays_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  // Years away from whenever this test runs.
  final clock = FakeClock(ist(2031, 3, 15, 12, 0));

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(db, clock: clock),
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('adding a holiday opens on the clock\'s today', (tester) async {
    await pump(tester, const HolidaysScreen());
    await tester.tap(find.text('Add holiday'));
    await settle(tester);
    expect(find.text('March 2031'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a booking date opens on the clock\'s today', (tester) async {
    await pump(tester, const BookingScreen());
    await tester.tap(find.text('Date'));
    await settle(tester);
    expect(find.text('March 2031'), findsOneWidget);
    await close(tester);
  });
}
