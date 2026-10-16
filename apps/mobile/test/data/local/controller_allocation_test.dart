/// Physical controller allocation (brief §1–§11): specific-pad allocation,
/// borrowing/relocation, double-allocation prevention, game player limits,
/// station availability, mid-session changes, accurate counts, RIFT mode, and
/// the validation messages — all against the Drift seed (8 pads, 2 per PS5;
/// EA FC supports 4 local players, Tekken 2).
library;

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_controller_allocation_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late LocalSessionRepository sessions;
  late LocalGroupSessionRepository groups;
  late LocalCatalogRepository catalog;
  late LocalCustomerRepository customers;
  late LocalControllerAllocationRepository alloc;
  late PricingSnapshot snapshot;
  late Customer who;

  final start = ist(2026, 10, 2, 18, 0); // Friday 18:00 IST — standard band.

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    sessions = LocalSessionRepository(db);
    groups = LocalGroupSessionRepository(db);
    catalog = LocalCatalogRepository(db);
    customers = LocalCustomerRepository(db);
    alloc = LocalControllerAllocationRepository(db);
    snapshot = await catalog.currentSnapshot();
    who = await customers.create(name: 'Arjun', phone: '9000000009');
  });

  tearDown(() async => db.close());

  Future<void> setResourceStatus(String id, String status) =>
      (db.update(db.resources)..where((t) => t.id.equals(id)))
          .write(ResourcesCompanion(status: Value(status)));

  Future startSingle({
    required String resourceId,
    required String resourceName,
    String activityCode = 'PS5',
    String? gameId,
    int? controllerCount,
    List<String>? controllerIds,
  }) =>
      sessions.start(StartSessionCommand(
        customerId: who.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: snapshot,
        resourceId: resourceId,
        resourceName: resourceName,
        activityCode: activityCode,
        gameId: gameId,
        controllerCount: controllerCount,
        controllerIds: controllerIds,
      ));

  GroupAssignmentDraft pa(int n, String resId, String resName,
          {String? game, List<String>? ids}) =>
      GroupAssignmentDraft(
        playerNumber: n,
        resourceId: resId,
        resourceName: resName,
        activityCode: 'PS5',
        gameId: game,
        controllerCount: ids?.length,
        controllerIds: ids,
      );

  Future createGroup(List<GroupAssignmentDraft> a, {int players = 4}) =>
      groups.create(CreateGroupCommand(
        primaryCustomerId: who.id,
        playerCount: players,
        purchasedControllerCount: players,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: snapshot,
        billingMode: GroupBillingMode.perSystem,
        assignments: a,
      ));

  // -------------------------------------------------------------------------
  group('four-player group + port capacity (brief §3, §6)', () {
    test('borrow two pads to HEX, seat four players on EA FC, reject a fifth',
        () async {
      // HEX has two pads; borrow GHOST's two so four are physically present.
      await alloc.moveController(
          controllerId: 'ctl_ghost_1', toResourceId: 'hex', kind: ControllerMoveKind.loan);
      await alloc.moveController(
          controllerId: 'ctl_ghost_2', toResourceId: 'hex', kind: ControllerMoveKind.loan);

      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
        pa(2, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_2']),
        pa(3, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_ghost_1']),
        pa(4, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_ghost_2']),
      ]);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect((await alloc.openAllocations()).length, 4);

      // A fifth player on EA FC (max 4) is rejected.
      final fifth = await groups.addAssignment(AddAssignmentCommand(
        groupId: r.valueOrNull!.id,
        at: start,
        playerNumber: 5,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerIds: const ['ctl_rift_1'],
      ));
      expect(fifth.isErr, isTrue);
      // A fifth hits both ceilings at once (EA FC = 4 players, PS5 = 4 ports);
      // the absolute port check reports first. The player-limit-only path is
      // covered distinctly by the Tekken (2-player) test below.
      expect(fifth.failureOrNull!.code,
          anyOf('players_exceeded', 'controllers_exceeded'));
    });
  });

  group('controller borrowing: location vs assignment (brief §5, §7)', () {
    test('a borrowed pad records its station separately from its assignment',
        () async {
      await alloc.moveController(
          controllerId: 'ctl_ghost_1', toResourceId: 'hex', kind: ControllerMoveKind.loan);
      final r = await startSingle(
          resourceId: 'hex',
          resourceName: 'HEX',
          gameId: 'g_eafc',
          controllerIds: ['ctl_ghost_1']);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);

      final pad = (await catalog.controllers()).firstWhere((c) => c.id == 'ctl_ghost_1');
      expect(pad.currentResourceId, 'hex', reason: 'physical location moved');
      expect(pad.homeResourceId, 'ghost', reason: 'home is unchanged');

      final open = await alloc.openAllocations();
      final a = open.firstWhere((x) => x.controllerId == 'ctl_ghost_1');
      expect(a.resourceId, 'hex', reason: 'used at HEX');

      final board = await alloc.dashboard();
      final view = board.pads.firstWhere((p) => p.controller.id == 'ctl_ghost_1');
      expect(view.borrowed, isTrue);
      expect(view.locationResourceId, 'hex');
      expect(view.inUse, isTrue);
    });
  });

  group('double-allocation prevention (brief §4, §9)', () {
    test('the same pad cannot be in two active allocations', () async {
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
      ], players: 2);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);

      final second = await groups.addAssignment(AddAssignmentCommand(
        groupId: r.valueOrNull!.id,
        at: start,
        playerNumber: 2,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerIds: const ['ctl_hex_1'], // already held by player 1
      ));
      expect(second.isErr, isTrue);
      expect(second.failureOrNull!.code, 'controller_taken');
    });

    test('the DB unique index rejects a second open allocation row directly',
        () async {
      await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      // Bypass the allocator and try to open a second row for the same pad.
      Future<void> insertDuplicate() => db.into(db.controllerAllocations).insert(
            ControllerAllocationRow(
              id: 'dup-1',
              controllerId: 'ctl_hex_1',
              scope: 'single',
              resourceId: 'hex',
              activityCode: 'PS5',
              startedAt: start,
              endedAt: null,
              createdAt: start,
            ),
          );
      await expectLater(insertDuplicate(), throwsA(isA<Exception>()));
    });

    test('allocating the same pad twice in one request is rejected', () async {
      final r = await startSingle(
          resourceId: 'hex',
          resourceName: 'HEX',
          gameId: 'g_eafc',
          controllerIds: ['ctl_hex_1', 'ctl_hex_1']);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controller_duplicate');
    });
  });

  group('game player limits (brief §6)', () {
    test('a 2-player game rejects a third player on one station', () async {
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_tekken8', ids: ['ctl_hex_1']),
        pa(2, 'hex', 'HEX', game: 'g_tekken8', ids: ['ctl_hex_2']),
      ], players: 3);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      await alloc.moveController(
          controllerId: 'ctl_void_1', toResourceId: 'hex', kind: ControllerMoveKind.loan);
      final third = await groups.addAssignment(AddAssignmentCommand(
        groupId: r.valueOrNull!.id,
        at: start,
        playerNumber: 3,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_tekken8',
        controllerIds: const ['ctl_void_1'],
      ));
      expect(third.isErr, isTrue);
      expect(third.failureOrNull!.code, 'players_exceeded');
    });

    test('a single session of a 2-player game rejects three controllers',
        () async {
      final r = await startSingle(
          resourceId: 'void',
          resourceName: 'VOID',
          gameId: 'g_tekken8',
          controllerIds: ['ctl_void_1', 'ctl_void_2', 'ctl_hex_1']);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'players_exceeded');
    });

    test('a VR session needs no controllers', () async {
      final r = await startSingle(
          resourceId: 'rift', resourceName: 'RIFT', activityCode: 'VR');
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect(await alloc.openAllocations(), isEmpty);
    });
  });

  group('station availability (brief §7)', () {
    test('a station under maintenance blocks a new group allocation', () async {
      await setResourceStatus('hex', 'maintenance');
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
      ], players: 1);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'resource_unavailable');
    });

    test('the dashboard reflects a station status', () async {
      await setResourceStatus('ghost', 'maintenance');
      final board = await alloc.dashboard();
      expect(board.stations.firstWhere((s) => s.id == 'ghost').status, 'maintenance');
    });
  });

  group('mid-session change preserves the timer + history (brief §8)', () {
    test('switching a player closes the old pad and opens the new at once',
        () async {
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
      ], players: 1);
      final group = r.valueOrNull!;
      final at = start.add(const Duration(minutes: 20));

      final sw = await groups.switchAssignment(SwitchAssignmentCommand(
        groupId: group.id,
        playerNumber: 1,
        at: at,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerIds: const ['ctl_void_1'],
      ));
      expect(sw.isOk, isTrue, reason: sw.failureOrNull?.display);

      // Parent timer untouched.
      final reloaded = await groups.getById(group.id);
      expect(reloaded!.startedAt, group.startedAt);
      expect(reloaded.scheduledEndAt, group.scheduledEndAt);

      // Old pad closed exactly at the switch; new pad open; no overlap.
      final hexHistory = await alloc.allocationsForController('ctl_hex_1');
      expect(hexHistory.single.endedAt, at);
      final voidHistory = await alloc.allocationsForController('ctl_void_1');
      expect(voidHistory.single.endedAt, isNull);
      expect(voidHistory.single.startedAt, at);

      expect((await alloc.openAllocations()).single.controllerId, 'ctl_void_1');
    });
  });

  group('accurate availability counts (brief §7)', () {
    test('totals reconcile with no double counting', () async {
      var board = await alloc.dashboard();
      expect(board.total, 8);
      expect(board.inUse, 0);
      expect(board.available, 8);

      await startSingle(
          resourceId: 'hex',
          resourceName: 'HEX',
          gameId: 'g_eafc',
          controllerIds: ['ctl_hex_1', 'ctl_hex_2']);
      board = await alloc.dashboard();
      expect(board.inUse, 2);
      expect(board.available, 6);
      expect(board.inUse + board.available, board.total);

      // A borrowed, in-use pad is still counted exactly once.
      await alloc.moveController(
          controllerId: 'ctl_ghost_1', toResourceId: 'void', kind: ControllerMoveKind.loan);
      await startSingle(
          resourceId: 'void',
          resourceName: 'VOID',
          gameId: 'g_eafc',
          controllerIds: ['ctl_ghost_1']);
      board = await alloc.dashboard();
      expect(board.inUse, 3);
      expect(board.available, 5);
      expect(board.pads.where((p) => p.controller.id == 'ctl_ghost_1').length, 1);

      // Retiring a pad drops it out of the total.
      await catalog.setControllerStatus('ctl_rift_2', ControllerStatus.retired);
      board = await alloc.dashboard();
      expect(board.total, 7);
    });
  });

  group('concurrency (brief §9)', () {
    test('two allocations racing for one pad: exactly one wins', () async {
      final first = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      expect(first.isOk, isTrue);
      // A held pad cannot even be walked away from its session...
      final move = await alloc.moveController(
          controllerId: 'ctl_hex_1', toResourceId: 'void', kind: ControllerMoveKind.loan);
      expect(move.failureOrNull?.code, 'controller_in_use');
      // ...and a second session trying to borrow it in loses atomically.
      final second = await sessions.start(StartSessionCommand(
        customerId: who.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: snapshot,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerCount: 1,
        controllerIds: const ['ctl_hex_1'],
        borrowControllerIds: const ['ctl_hex_1'],
      ));
      expect(second.isErr, isTrue);
      expect(second.failureOrNull!.code, 'controller_taken');
      expect((await alloc.openAllocations()).length, 1);
    });
  });

  group('RIFT PS5-xor-VR (brief §1)', () {
    test('a mode-locked RIFT refuses the other activity', () async {
      expect((await alloc.setResourceMode('rift', 'PS5')).isOk, isTrue);
      final vr = await startSingle(
          resourceId: 'rift', resourceName: 'RIFT', activityCode: 'VR');
      expect(vr.isErr, isTrue);
      expect(vr.failureOrNull!.code, 'mode_locked');
    });

    test('mode cannot be switched while RIFT is occupied', () async {
      await alloc.setResourceMode('rift', 'PS5');
      final s = await startSingle(
          resourceId: 'rift', resourceName: 'RIFT', gameId: 'g_eafc', controllerIds: ['ctl_rift_1']);
      expect(s.isOk, isTrue, reason: s.failureOrNull?.display);
      final flip = await alloc.setResourceMode('rift', 'VR');
      expect(flip.isErr, isTrue);
      expect(flip.failureOrNull!.code, 'mode_switch_busy');
    });
  });

  group('validation messages (brief §10)', () {
    test('a faulty pad cannot be allocated', () async {
      await catalog.setControllerStatus('ctl_hex_1', ControllerStatus.faulty);
      final r = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controller_unusable');
      expect(r.failureOrNull!.message, contains('HEX-1'));
    });

    test('a pad at another station must be moved first', () async {
      final r = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_void_1']);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controller_elsewhere');
      expect(r.failureOrNull!.fix, contains('Move'));
    });
  });

  group('allocations close on end / void / reconfigure (brief §8)', () {
    final end = start.add(const Duration(hours: 1));

    test('ending a single session frees its pads', () async {
      final r = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      expect((await alloc.openAllocations()).length, 1);
      await sessions.end(EndSessionCommand(
          sessionId: r.valueOrNull!.id, actualEndedAt: end, charges: const [], billedAmountPaise: 0));
      expect(await alloc.openAllocations(), isEmpty);
    });

    test('voiding a single session frees its pads', () async {
      final r = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      await sessions.voidSession(r.valueOrNull!.id, 'correction');
      expect(await alloc.openAllocations(), isEmpty);
    });

    test('reconfiguring a single session closes the old pad, opens the new, '
        'and keeps the timer', () async {
      final r = await startSingle(
          resourceId: 'hex', resourceName: 'HEX', gameId: 'g_eafc', controllerIds: ['ctl_hex_1']);
      final sess = r.valueOrNull!;
      final at = start.add(const Duration(minutes: 15));
      final rc = await sessions.reconfigure(ReconfigureCommand(
        sessionId: sess.id,
        at: at,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllerIds: const ['ctl_void_1'],
      ));
      expect(rc.isOk, isTrue, reason: rc.failureOrNull?.display);
      expect((await alloc.allocationsForController('ctl_hex_1')).single.endedAt, at);
      expect((await alloc.allocationsForController('ctl_void_1')).single.endedAt, isNull);
      final reloaded = await sessions.getById(sess.id);
      expect(reloaded!.startedAt, sess.startedAt);
      expect(reloaded.scheduledEndAt, sess.scheduledEndAt);
    });

    test('ending a group frees all pads', () async {
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
      ], players: 1);
      await groups.end(EndGroupCommand(
          groupId: r.valueOrNull!.id, actualEndedAt: end, charges: const [], billedAmountPaise: 0));
      expect(await alloc.openAllocations(), isEmpty);
    });

    test('voiding a group frees all pads', () async {
      final r = await createGroup([
        pa(1, 'hex', 'HEX', game: 'g_eafc', ids: ['ctl_hex_1']),
      ], players: 1);
      await groups.voidGroup(r.valueOrNull!.id, 'correction');
      expect(await alloc.openAllocations(), isEmpty);
    });
  });
}
