import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/sync/presentation/sync_screen.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_transport.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  late ScriptedTransport server;
  late SyncEngine engine;
  late SyncRecorder recorder;
  late CloudBinding binding;
  var signedOut = 0;
  final clock = FakeClock(DateTime.utc(2026, 10, 11, 10));

  setUp(() async {
    db = await seededMemoryDb();
    server = ScriptedTransport();
    engine = SyncEngine(db: db, transport: server, arenaId: 'arena', clock: clock);
    recorder = SyncRecorder(db, actor: () => 'u2', clock: clock);
    signedOut = 0;
    binding = CloudBinding(
      arenaId: 'arena',
      arenaName: 'Test Arena',
      userId: 'u2',
      email: 'staff@arena.test',
      engine: engine,
      recorder: recorder,
      clock: OffsetClock(clock, Duration.zero),
      signOut: () async => signedOut++,
      addStaffByEmail: (_, _, _) async {},
      changePassword: (_) async {},
    );
  });
  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  Widget host(Widget child, {List<dynamic> extra = const []}) => ProviderScope(
        overrides: [
          ...testOverrides(db, clock: clock),
          cloudBindingProvider.overrideWithValue(binding),
          ...extra.cast(),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('offline with a change waiting: says so, never "synced"',
      (tester) async {
    await tester.runAsync(() async {
      await LocalCustomerRepository(db, clock, recorder).createGuest();
      server.pushThrows = SyncOfflineException('no route');
      await engine.syncNow();
    });
    await tester.pumpWidget(host(const ConnectionStatus()));
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.textContaining('1 saved here, not sent yet'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('a refused payment is listed with its amount and the reason',
      (tester) async {
    await tester.runAsync(() async {
      final who = await LocalCustomerRepository(db, clock, recorder).createGuest();
      final sessions = LocalSessionRepository(db, clock, recorder);
      final started = await sessions.start(StartSessionCommand(
        customerId: who.id,
        startedAt: clock.now(),
        scheduledEndAt: clock.now().add(const Duration(hours: 1)),
        snapshot: await LocalCatalogRepository(db).currentSnapshot(),
        resourceId: 'pool1',
        resourceName: 'Pool Table 1',
        activityCode: 'POOL',
      ));
      await sessions.recordPayment(RecordPaymentCommand(
          sessionId: started.valueOrNull!.id,
          amountPaise: 15000,
          method: PaymentMethod.cash));
      server.onPush = (o) => o.kind == 'customer.create'
          ? OpResult(opId: o.opId, status: 'applied')
          : OpResult(opId: o.opId, status: 'rejected', error: 'resource_busy');
      await engine.syncNow();
    });
    await tester.pumpWidget(host(const SyncScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Needs attention (2)'), findsOneWidget);
    expect(find.textContaining('Payment ₹150'), findsOneWidget);
    expect(find.textContaining('another device started it first'), findsWidgets);
    await tester.tap(find.text('Seen').first);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Needs attention (1)'), findsOneWidget);
    await disposeApp(tester);
  });

  test('permissions follow the synced staff row; access off signs out',
      () async {
    final container = ProviderContainer(overrides: [
      ...testOverrides(db,
          clock: clock,
          auth: () => CloudAuthController(const AppUser(
              id: 'u2', name: 'Alan', perms: {Permission.start}))),
      cloudBindingProvider.overrideWithValue(binding),
    ]);
    addTearDown(container.dispose);
    final seen = <AppUser?>[];
    container.listen(authControllerProvider, (_, next) => seen.add(next),
        fireImmediately: true);
    // An owner granted "bill" on another device; the pull lands it here.
    await (db.update(db.users)..where((t) => t.id.equals('u2'))).write(
        UsersCompanion(
            perms: Value(Permission.codesOf({Permission.start, Permission.bill}))));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last?.can(Permission.bill), isTrue);
    await (db.update(db.users)..where((t) => t.id.equals('u2')))
        .write(const UsersCompanion(active: Value(false)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last, isNull);
    expect(signedOut, 1);
  });
}

/// Unmounts the tree and lets drift close its query streams (the repo's
/// widget-test idiom, see floor_screen_test).
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}
