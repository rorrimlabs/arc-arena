/// Widget-level: the End sheet settles only what is still due. Money taken
/// while the session ran (Take payment) is already in the till; collecting the
/// full bill again would double-count it in Money and Reports.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  final now = ist(2026, 10, 2, 19, 2); // standard band

  setUp(() async => db = await seededMemoryDb());
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('an advance is not collected again at the end', (tester) async {
    tester.view.physicalSize = const Size(1179, 5200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final who = await LocalCustomerRepository(db).create(name: 'Meera');
    final sessions = LocalSessionRepository(db);
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: now.subtract(const Duration(hours: 1)),
      scheduledEndAt: now,
      snapshot: await LocalCatalogRepository(db).currentSnapshot(),
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 1,
    ));
    expect(started.isOk, isTrue, reason: '${started.failureOrNull?.message}');
    final id = started.valueOrNull!.id;
    expect((await sessions.recordPayment(RecordPaymentCommand(
            sessionId: id, amountPaise: 5000, method: PaymentMethod.cash)))
        .isOk, isTrue);
    final active = (await sessions.active()).single;

    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(db, clock: FakeClock(now)),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEndSessionSheet(context, active),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.textContaining('Already collected ₹50'), findsOneWidget);

    await tester.tap(find.text('End & record'));
    await settle(tester);

    final ended = (await sessions.getById(id))!;
    expect(ended.status, SessionStatus.completed);
    final billed = ended.billedAmountPaise!;
    expect(billed, greaterThan(5000));
    final payments = await sessions.paymentsFor(id);
    expect(payments.map((p) => p.amountPaise), unorderedEquals([5000, billed - 5000]),
        reason: 'only the balance was recorded at the end');
    expect(ended.paymentStatus, PaymentStatus.paid);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
