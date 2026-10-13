/// Today's money reads both payment ledgers: group bills are paid into their
/// own table, and Money / the Today takings card used to miss them.
library;

import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/money/application/money_today.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  // Friday 7 PM IST — standard band.
  final now = ist(2026, 10, 2, 19, 0);

  setUp(() async {
    db = await seededMemoryDb();
    container = ProviderContainer(overrides: testOverrides(db, clock: FakeClock(now)));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a group payment counts in today\'s money next to a single one', () async {
    final who = await LocalCustomerRepository(db).create(name: 'Rahul');
    final snapshot = await LocalCatalogRepository(db).currentSnapshot();
    final sessions = container.read(sessionRepositoryProvider);
    final groups = container.read(groupSessionRepositoryProvider);

    final single = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: now.subtract(const Duration(minutes: 30)),
      scheduledEndAt: now.add(const Duration(minutes: 30)),
      snapshot: snapshot,
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 1,
    ));
    expect(single.isOk, isTrue, reason: single.failureOrNull?.message);
    expect((await sessions.recordPayment(RecordPaymentCommand(
            sessionId: single.valueOrNull!.id,
            amountPaise: 10000,
            method: PaymentMethod.upi)))
        .isOk, isTrue);

    final group = await groups.create(CreateGroupCommand(
      primaryCustomerId: who.id,
      playerCount: 2,
      purchasedControllerCount: 2,
      startedAt: now.subtract(const Duration(minutes: 30)),
      scheduledEndAt: now.add(const Duration(minutes: 30)),
      snapshot: snapshot,
      billingMode: GroupBillingMode.perSystem,
      assignments: const [
        GroupAssignmentDraft(
            playerNumber: 1, resourceId: 'void', resourceName: 'VOID', activityCode: 'PS5'),
        GroupAssignmentDraft(
            playerNumber: 2, resourceId: 'ghost', resourceName: 'GHOST', activityCode: 'PS5'),
      ],
    ));
    expect(group.isOk, isTrue, reason: group.failureOrNull?.message);
    expect((await groups.recordPayment(RecordGroupPaymentCommand(
            groupId: group.valueOrNull!.id,
            amountPaise: 30000,
            method: PaymentMethod.cash)))
        .isOk, isTrue);

    final payments = await container.read(todayPaymentsProvider.future);
    expect([for (final p in payments) p.amountPaise]..sort(), [10000, 30000]);

    final byMethod = {
      for (final b in await container.read(todayMethodBreakdownProvider.future))
        b.method: b.totalPaise,
    };
    expect(byMethod[PaymentMethod.cash], 30000);
    expect(byMethod[PaymentMethod.upi], 10000);

    final hourly = await container.read(todayHourlyTakingsProvider.future);
    expect(hourly.fold<int>(0, (a, v) => a + v), 40000);
  });
}
