import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/services/group_billing.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late LocalGroupSessionRepository groups;
  late LocalSessionRepository sessions;
  late LocalCatalogRepository catalog;
  late LocalCustomerRepository customers;
  late PricingSnapshot snapshot;
  late Customer rahul;

  const billing = GroupBilling();
  // Friday 18:00 IST — standard band (happy hour is 14:00–17:00 weekdays).
  final start = ist(2026, 10, 2, 18, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    groups = LocalGroupSessionRepository(db);
    sessions = LocalSessionRepository(db);
    catalog = LocalCatalogRepository(db);
    customers = LocalCustomerRepository(db);
    snapshot = await catalog.currentSnapshot();
    rahul = await customers.create(name: 'Rahul', phone: '9000000001');
  });

  tearDown(() async => db.close());

  GroupAssignmentDraft pa(int n, String resId, String resName,
          {String? game, int ctrl = 1}) =>
      GroupAssignmentDraft(
        playerNumber: n,
        resourceId: resId,
        resourceName: resName,
        activityCode: 'PS5',
        gameId: game,
        controllerCount: ctrl,
      );

  Future<GroupSession> createGroup(
    List<GroupAssignmentDraft> assignments, {
    int players = 3,
    int controllers = 3,
    int durationMin = 60,
    GroupBillingMode mode = GroupBillingMode.perSystem,
  }) async {
    final r = await groups.create(CreateGroupCommand(
      primaryCustomerId: rahul.id,
      playerCount: players,
      purchasedControllerCount: controllers,
      startedAt: start,
      scheduledEndAt: start.add(Duration(minutes: durationMin)),
      snapshot: snapshot,
      billingMode: mode,
      assignments: assignments,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  Future<GroupSession> endGroup(String id, DateTime at,
      {GroupBillingMode? mode}) async {
    final g = (await groups.activeGroups())
        .firstWhere((x) => x.group.id == id);
    final bill = billing.bill(
      snapshot: snapshot,
      assignments: g.assignments,
      mode: mode ?? g.group.billingMode,
      purchasedControllerCount: g.group.purchasedControllerCount,
      groupStart: g.group.startedAt,
      openEndAt: at,
    );
    final r = await groups.end(EndGroupCommand(
      groupId: id,
      actualEndedAt: at,
      charges: bill.charges,
      billedAmountPaise: bill.total.value,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!;
  }

  /// Carries a spare pad from GHOST onto [resourceId], the way staff would.
  Future<void> lendControllerTo(String resourceId) async {
    final catalog = LocalCatalogRepository(db);
    final spare = (await catalog.controllers()).firstWhere(
      (c) => c.currentResourceId == 'ghost' && c.status.isUsable,
    );
    await catalog.upsertController(spare.copyWith(
      currentResourceId: resourceId,
      loanReturnTo: 'ghost',
    ));
  }

  test('1 · three players on one system bill at the combined-controller rate',
      () async {
    // A station ships with two pads, so seating three players on one PS5
    // genuinely needs a third carried over — the real-world move this feature
    // exists to manage.
    await lendControllerTo('hex');

    final g = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'hex', 'HEX', game: 'g_wwe'),
      pa(3, 'hex', 'HEX', game: 'g_wwe'),
    ]);
    final active = (await groups.activeGroups()).single;
    expect(active.openAssignments.length, 3);
    expect(active.occupiedResourceIds, {'hex'}); // only one system is busy

    final ended = await endGroup(g.id, start.add(const Duration(minutes: 60)));
    // Three controllers on one PS5 for 60 min → the 3-controller rate, ₹390.
    expect(ended.billedAmountPaise, 39000);
  });

  test('2 · three players on three systems each bill their own system',
      () async {
    final g = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'void', 'VOID', game: 'g_wwe'),
      pa(3, 'ghost', 'GHOST', game: 'g_wwe'),
    ]);
    final active = (await groups.activeGroups()).single;
    expect(active.openAssignments.length, 3);
    expect(active.occupiedResourceIds, {'hex', 'void', 'ghost'});
    expect((await groups.openAssignments()).length, 3);

    final ended = await endGroup(g.id, start.add(const Duration(minutes: 60)));
    // Three single-controller systems for 60 min → 3 × ₹150 = ₹450.
    expect(ended.billedAmountPaise, 45000);
  });

  test('3 · a player switching systems closes and reopens at the same instant',
      () async {
    final g = await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
        players: 1, controllers: 1);
    final at = start.add(const Duration(minutes: 30));
    final r = await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 1,
      at: at,
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);

    final segs = await groups.assignmentsFor(g.id);
    expect(segs.length, 2);
    expect(segs[0].endedAt, at); // closed exactly at the switch
    expect(segs[1].startedAt, at); // opened exactly at the switch — no gap
    expect(segs[1].resourceId, 'void');
    expect(segs[1].isOpen, isTrue);

    // HEX is free again; VOID is now the only open system for the group.
    expect((await groups.openAssignments()).single.resourceId, 'void');
  });

  test('4 · a player changing game stays on the same system', () async {
    final g = await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
        players: 1, controllers: 1);
    final r = await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 1,
      at: start.add(const Duration(minutes: 20)),
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      gameId: 'g_mk1',
      controllerCount: 1,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    final segs = await groups.assignmentsFor(g.id);
    expect(segs.length, 2);
    expect(segs[1].resourceId, 'hex');
    expect(segs[1].gameId, 'g_mk1');
  });

  test('5 · a system becomes free after a player ends, group stays active',
      () async {
    final g = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'void', 'VOID', game: 'g_wwe'),
    ], players: 2, controllers: 2);
    final r = await groups.endAssignment(EndAssignmentCommand(
      groupId: g.id,
      playerNumber: 2,
      at: start.add(const Duration(minutes: 40)),
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    final open = await groups.openAssignments();
    expect(open.map((a) => a.resourceId), ['hex']); // VOID freed
    expect((await groups.getById(g.id))!.status, GroupSessionStatus.active);
  });

  group('6 · occupancy blocks across the single and group worlds', () {
    test('a single session cannot take a group-occupied system', () async {
      await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
          players: 1, controllers: 1);
      final r = await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(minutes: 60)),
        snapshot: snapshot,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      expect(r.failureOrNull?.code, 'resource_busy');
    });

    test('a group cannot take a system a single session is using', () async {
      await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(minutes: 60)),
        snapshot: snapshot,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      final r = await groups.create(CreateGroupCommand(
        primaryCustomerId: rahul.id,
        playerCount: 1,
        purchasedControllerCount: 1,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(minutes: 60)),
        snapshot: snapshot,
        billingMode: GroupBillingMode.perSystem,
        assignments: [pa(1, 'void', 'VOID', game: 'g_wwe')],
      ));
      expect(r.failureOrNull?.code, 'resource_busy');
    });
  });

  test('7 · game compatibility is checked before a switch', () async {
    final g = await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
        players: 1, controllers: 1);
    // EA FC is not playable on GHOST (seed §4 override).
    final r = await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 1,
      at: start.add(const Duration(minutes: 10)),
      resourceId: 'ghost',
      resourceName: 'GHOST',
      activityCode: 'PS5',
      gameId: 'g_eafc',
      controllerCount: 1,
    ));
    expect(r.failureOrNull?.code, 'not_playable');
    // The player is untouched — still one open assignment on HEX.
    expect((await groups.openAssignments()).single.resourceId, 'hex');
  });

  test('8 · the shared countdown never moves on switch / game change / add',
      () async {
    final g = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'void', 'VOID', game: 'g_wwe'),
    ], players: 3, controllers: 3);
    final start0 = g.startedAt;
    final end0 = g.scheduledEndAt;
    final probe = start.add(const Duration(minutes: 15));
    final remaining0 = SessionTimer(startedAt: start0, scheduledEndAt: end0)
        .remaining(probe);

    // Add player 3, switch player 1, change player 2's game — none of these
    // may touch the parent window.
    await groups.addAssignment(AddAssignmentCommand(
      groupId: g.id,
      at: start.add(const Duration(minutes: 5)),
      playerNumber: 3,
      resourceId: 'ghost',
      resourceName: 'GHOST',
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    ));
    await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 1,
      at: start.add(const Duration(minutes: 10)),
      resourceId: 'rift',
      resourceName: 'RIFT',
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    ));
    await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 2,
      at: start.add(const Duration(minutes: 12)),
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      gameId: 'g_mk1',
      controllerCount: 1,
    ));

    final after = (await groups.getById(g.id))!;
    expect(after.startedAt, start0);
    expect(after.scheduledEndAt, end0);
    expect(
      SessionTimer(startedAt: after.startedAt, scheduledEndAt: after.scheduledEndAt)
          .remaining(probe),
      remaining0,
    );
  });

  test('9 · extending the group moves the shared end and records history',
      () async {
    final g = await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
        players: 1, controllers: 1);
    final newEnd = start.add(const Duration(minutes: 120));
    final r = await groups.extend(ExtendGroupCommand(
      groupId: g.id,
      addedMinutes: 60,
      newEndAt: newEnd,
      addedAmountPaise: 15000,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    expect((await groups.getById(g.id))!.scheduledEndAt, newEnd);
    final history = await groups.extensionsFor(g.id);
    expect(history.length, 1);
    expect(history.single.newEndAt, newEnd);
  });

  test('10 · assignment history has no lost or duplicated time', () async {
    final g = await createGroup([pa(1, 'hex', 'HEX', game: 'g_wwe')],
        players: 1, controllers: 1);
    await groups.switchAssignment(SwitchAssignmentCommand(
      groupId: g.id,
      playerNumber: 1,
      at: start.add(const Duration(minutes: 25)),
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    ));
    final segs = await groups.assignmentsFor(g.id);
    expect(segs.length, 2);
    // The closed segment ends exactly where the next begins — no gap, no overlap.
    expect(segs[0].endedAt, segs[1].startedAt);
    expect(segs.where((s) => s.isOpen).length, 1);
  });

  test('11 · final billing follows the configured policy', () async {
    // per-system: three single-controller systems → ₹450.
    final perSystem = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'void', 'VOID', game: 'g_wwe'),
      pa(3, 'ghost', 'GHOST', game: 'g_wwe'),
    ]);
    final a = await endGroup(perSystem.id, start.add(const Duration(minutes: 60)));
    expect(a.billedAmountPaise, 45000);

    // shared-controller-pool: three controllers billed once → ₹390.
    final pooled = await createGroup([
      pa(1, 'hex', 'HEX', game: 'g_wwe'),
      pa(2, 'void', 'VOID', game: 'g_wwe'),
      pa(3, 'ghost', 'GHOST', game: 'g_wwe'),
    ], mode: GroupBillingMode.sharedControllerPool);
    final b = await endGroup(pooled.id, start.add(const Duration(minutes: 60)));
    expect(b.billedAmountPaise, 39000);
  });
}
