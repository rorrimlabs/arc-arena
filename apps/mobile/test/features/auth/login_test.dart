import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('locked app shows the PIN login; owner PIN signs in to Today',
      (tester) async {
    // auth: AuthController.new → the real (null) controller, so we see login.
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(db, auth: AuthController.new),
      child: const ArenaOpsApp(),
    ));
    await settle(tester);

    // Names come from the seeded accounts, not from this test: renaming the
    // staff in `seed_data` must not break the login flow.
    final accounts = await LocalUserRepository(db).activeUsers();
    final owner = accounts.firstWhere((u) => u.isOwner);
    final staff = accounts.firstWhere((u) => !u.isOwner);

    expect(find.text("Who's on shift?"), findsOneWidget);
    expect(find.text(owner.name), findsOneWidget);
    expect(find.text(staff.name), findsOneWidget);

    await tester.tap(find.text(owner.name));
    await settle(tester);
    expect(find.text('Enter PIN'), findsOneWidget);

    // Owner PIN is 1111.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    await settle(tester);

    // Signed in as owner → lands on Today with all five tabs.
    expect(find.text('Takings today'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));

    await disposeApp(tester);
  });

  testWidgets('staff land on Floor and never see Money / Reports / Today',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(db, auth: TestStaffAuth.new),
      child: const ArenaOpsApp(),
    ));
    await settle(tester);

    // Staff home is the Floor.
    expect(find.text('New Session'), findsWidgets);
    // Only Floor + More in the nav.
    expect(find.byType(NavigationDestination), findsNWidgets(2));
    // "Floor" shows twice (screen header + nav label); "More" only in the nav.
    expect(find.text('Floor'), findsWidgets);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Money'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Today'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('shows empty state when no staff accounts exist', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...testOverrides(db, auth: AuthController.new),
        usersProvider.overrideWith((ref) async => const []),
      ],
      child: const ArenaOpsApp(),
    ));
    await settle(tester);

    expect(find.text('No staff accounts found'), findsOneWidget);
    expect(
      find.text(
        'Add or invite staff members from the admin dashboard to get started.',
      ),
      findsOneWidget,
    );

    await disposeApp(tester);
  });

  testWidgets('shows error state when accounts fail to load', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...testOverrides(db, auth: AuthController.new),
        usersProvider.overrideWithValue(
          AsyncError(Exception('db error'), StackTrace.current),
        ),
      ],
      child: const ArenaOpsApp(),
    ));
    await settle(tester);

    expect(find.text('Could not load accounts'), findsOneWidget);

    await disposeApp(tester);
  });
}
