/// Booking check-in with physical controllers, and the group game rules
/// enforced BEFORE anything is saved (start / add / switch / change), through
/// the application actions.
library;

import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/app/controllers/pad_board_loader.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_controller_allocation_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late LocalSessionRepository sessionsRepo;
  late LocalGroupSessionRepository groupsRepo;
  late LocalBookingRepository bookingsRepo;
  late LocalCatalogRepository catalog;
  late LocalControllerAllocationRepository alloc;
  late BookingActions bookings;
  late GroupSessionActions groups;
  late PadBoardLoader boards;
  late String customerId;

  const staff = PermissionGuard(AppUser(
    id: 'u2',
    name: 'Staff',
    perms: {Permission.start, Permission.bill, Permission.discount},
  ));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    clock = FakeClock(ist(2026, 10, 2, 14, 0));
    sessionsRepo = LocalSessionRepository(db, clock);
    groupsRepo = LocalGroupSessionRepository(db, clock);
    bookingsRepo = LocalBookingRepository(db, clock);
    catalog = LocalCatalogRepository(db);
    alloc = LocalControllerAllocationRepository(db, clock);
    boards = PadBoardLoader(
        catalog: catalog, sessions: sessionsRepo, groups: groupsRepo, pads: alloc);
    bookings = BookingActions(
      bookings: bookingsRepo,
      sessions: sessionsRepo,
      catalog: catalog,
      clock: clock,
      groups: groupsRepo,
      boards: boards,
    );
    groups = GroupSessionActions(
      groups: groupsRepo,
      sessions: sessionsRepo,
      catalog: catalog,
      bookings: bookingsRepo,
      clock: clock,
      guard: staff,
      pads: alloc,
    );
    customerId =
        (await LocalCustomerRepository(db, clock).create(name: 'Rahul')).id;
  });

  tearDown(() async => db.close());

  Future<Set<String>> held() async =>
      {for (final a in await alloc.openPadAllocations()) a.controllerId};

  Future<Booking> book({
    String? resourceId,
    String activity = 'PS5',
    String? gameId = 'g_eafc',
    int? controllers = 2,
  }) async {
    final r = await bookings.createBooking(BookingDraft(
      customerId: customerId,
      activityCode: activity,
      date: fridayDate,
      startMinuteOfDay: 19 * 60,
      durationMinutes: 60,
      gameId: gameId,
      resourceId: resourceId,
      controllerRequirement: controllers,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    clock.set(ist(2026, 10, 2, 19, 2)); // the party arrives
    return r.valueOrNull!;
  }

  group('booking check-in', () {
    test('plans the booked system and pre-picks the booked pads', () async {
      final b = await book(resourceId: 'void');
      final plan = (await bookings.planCheckIn(b)).valueOrNull!;
      expect(plan.resource.id, 'void');
      expect(plan.requestedControllers, 2);
      final board = await boards.load(resourceId: 'void');
      final choice = ControllerChoice.tracked(requested: 2).reconcile(board);
      expect(choice.padIds, ['ctl_void_1', 'ctl_void_2']);

      final s = await bookings.checkIn(b,
          controllers: choice, resourceId: plan.resource.id);
      expect(s.isOk, isTrue, reason: s.failureOrNull?.display);
      expect(await held(), {'ctl_void_1', 'ctl_void_2'});
      expect((await bookingsRepo.getById(b.id))!.status, BookingStatus.checkedIn);
    });

    test('four booked at a two-pad station: refused until two are borrowed',
        () async {
      final b = await book(resourceId: 'void', controllers: 4);
      var board = await boards.load(resourceId: 'void');
      var choice = ControllerChoice.tracked(requested: 4).reconcile(board);
      expect(choice.shortfall, 2);
      final refused = await bookings.checkIn(b, controllers: choice);
      expect(refused.failureOrNull?.code, 'controllers_unavailable');
      expect((await bookingsRepo.getById(b.id))!.status, BookingStatus.booked,
          reason: 'nothing written on a refused check-in');
      expect(await sessionsRepo.active(), isEmpty);

      choice = choice.toggle('ctl_hex_1', board).toggle('ctl_hex_2', board);
      final s = await bookings.checkIn(b, controllers: choice);
      expect(s.isOk, isTrue, reason: s.failureOrNull?.display);
      expect((await sessionsRepo.active()).single.current.controllerCount, 4);
      final hex1 = await alloc.movesForController('ctl_hex_1');
      expect(hex1.single.toResourceId, 'void');
      expect(hex1.single.sessionRef, Controller.sessionRef(s.valueOrNull!.id));
      board = await boards.load(resourceId: 'hex');
      expect(board.inventory.freeHere, 0, reason: 'both HEX pads now at VOID');
    });

    test('a bare count is still checked against the free pads', () async {
      final b = await book(resourceId: 'void', controllers: 4);
      final r = await bookings.checkIn(b); // no pads picked (legacy caller)
      expect(r.failureOrNull?.message,
          '4 controllers needed, only 2 free at VOID.');
    });

    test('the game local-player limit applies at check-in', () async {
      final b = await book(resourceId: 'hex', gameId: 'g_tekken8');
      final board = await boards.load(resourceId: 'hex');
      final three = ControllerChoice.tracked(requested: 2)
          .reconcile(board)
          .toggle('ctl_void_1', board);
      final r = await bookings.checkIn(b, controllers: three);
      expect(r.failureOrNull?.code, 'players_exceeded');
    });

    test('any-system booking goes where the pads are, and never onto a '
        'station a group is using', () async {
      // HEX has a faulty pad (1 free); a group occupies VOID.
      await catalog.setControllerStatus('ctl_hex_2', ControllerStatus.faulty);
      final g = await groups.create(GroupSessionDraft(
        primaryCustomerId: customerId,
        playerCount: 1,
        purchasedControllerCount: 1,
        players: [
          GroupPlayerDraft(
            playerNumber: 1,
            resourceId: 'void',
            resourceName: 'VOID',
            activityCode: 'PS5',
            gameId: 'g_wwe',
            controllers: const ControllerChoice.tracked(
                requested: 1, padIds: ['ctl_void_1']),
          ),
        ],
      ));
      expect(g.isOk, isTrue, reason: g.failureOrNull?.display);
      final b = await book(controllers: 2); // any system, EA FC
      final plan = (await bookings.planCheckIn(b)).valueOrNull!;
      // HEX has only one free pad, VOID is the group's, GHOST can't run EA FC.
      expect(plan.resource.id, 'rift');
      expect(plan.alternatives, isTrue);
    });

    test('an activity without controllers checks in without pads', () async {
      final b = await book(
          resourceId: 'rift', activity: 'VR', gameId: null, controllers: null);
      final s = await bookings.checkIn(b);
      expect(s.isOk, isTrue, reason: s.failureOrNull?.display);
      expect(await held(), isEmpty);
    });
  });

  group('group game rules before anything is saved', () {
    GroupPlayerDraft p(int n, String res, List<String> pads,
            {String game = 'g_tekken8', Set<String> borrow = const {}}) =>
        GroupPlayerDraft(
          playerNumber: n,
          resourceId: res,
          resourceName: res.toUpperCase(),
          activityCode: 'PS5',
          gameId: game,
          controllers: ControllerChoice.tracked(
              requested: pads.length, padIds: pads, borrowIds: borrow),
        );

    Future<GroupSession> start(List<GroupPlayerDraft> players) async {
      final r = await groups.create(GroupSessionDraft(
        primaryCustomerId: customerId,
        playerCount: players.length,
        purchasedControllerCount: players.length,
        players: players,
      ));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      return r.valueOrNull!;
    }

    test('one player holding more pads than the game allows is refused at '
        'preview, and by the repository', () async {
      final draft = GroupSessionDraft(
        primaryCustomerId: customerId,
        playerCount: 1,
        purchasedControllerCount: 3,
        players: [
          p(1, 'hex', ['ctl_hex_1', 'ctl_hex_2', 'ctl_void_1'],
              borrow: {'ctl_void_1'}),
        ],
      );
      final preview = await groups.previewCreate(draft);
      expect(preview.failureOrNull?.code, 'players_exceeded');
      expect(preview.failureOrNull?.message,
          startsWith('Player 1: Tekken 8 supports 2 local players'));
      // Direct to the repository (no UI): still refused, nothing moved.
      final direct = await groupsRepo.create(CreateGroupCommand(
        primaryCustomerId: customerId,
        playerCount: 1,
        purchasedControllerCount: 3,
        startedAt: clock.now(),
        scheduledEndAt: clock.now().add(const Duration(hours: 1)),
        snapshot: await catalog.currentSnapshot(),
        billingMode: GroupBillingMode.perSystem,
        assignments: const [
          GroupAssignmentDraft(
            playerNumber: 1,
            resourceId: 'hex',
            resourceName: 'HEX',
            activityCode: 'PS5',
            gameId: 'g_tekken8',
            controllerIds: ['ctl_hex_1', 'ctl_hex_2', 'ctl_void_1'],
            borrowControllerIds: ['ctl_void_1'],
          ),
        ],
      ));
      expect(direct.failureOrNull?.code, 'players_exceeded');
      expect(await alloc.movesForController('ctl_void_1'), isEmpty);
    });

    test('adding a third Tekken controller to a shared station is caught '
        'before save', () async {
      final g = await start([
        p(1, 'hex', ['ctl_hex_1']),
        p(2, 'hex', ['ctl_hex_2']),
      ]);
      const third = ControllerChoice.tracked(
          requested: 1, padIds: ['ctl_void_1'], borrowIds: {'ctl_void_1'});
      final preview = await groups.previewAssignment(
        group: g,
        playerNumber: 3,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_tekken8',
        controllers: third,
      );
      expect(preview.failureOrNull?.code, 'players_exceeded');
      final add = await groups.addPlayer(
        groupId: g.id,
        playerNumber: 3,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        gameId: 'g_tekken8',
        controllers: third,
      );
      expect(add.failureOrNull?.code, 'players_exceeded');
      expect((await groupsRepo.assignmentsFor(g.id)).length, 2);
      expect(await alloc.movesForController('ctl_void_1'), isEmpty);
    });

    test('a change of controllers past the game limit is refused, nothing '
        'changes', () async {
      final g = await start([p(1, 'hex', ['ctl_hex_1'])]);
      final current =
          (await groupsRepo.activeGroups()).single.currentForPlayer(1)!;
      final r = await groups.changeControllers(
        groupId: g.id,
        current: current,
        controllers: const ControllerChoice.tracked(
            requested: 3,
            padIds: ['ctl_hex_1', 'ctl_hex_2', 'ctl_void_1'],
            borrowIds: {'ctl_void_1'}),
      );
      expect(r.failureOrNull?.code, 'players_exceeded');
      expect(await held(), {'ctl_hex_1'});
      expect((await groupsRepo.assignmentsFor(g.id)).length, 1);
    });

    test('a game change is checked for the player limit and for teammates '
        'sharing the system', () async {
      final g = await start([
        p(1, 'hex', ['ctl_hex_1'], game: 'g_wwe'),
        p(2, 'hex', ['ctl_hex_2'], game: 'g_wwe'),
      ]);
      final p1 =
          (await groupsRepo.activeGroups()).single.currentForPlayer(1)!;
      // Teammate on WWE at the same station: a different game is refused.
      final conflict =
          await groups.changeGame(groupId: g.id, current: p1, gameId: 'g_nba');
      expect(conflict.failureOrNull?.code, 'game_conflict');
      expect((await groupsRepo.assignmentsFor(g.id)).length, 2,
          reason: 'nothing saved');
    });

    test('a single player with two pads cannot switch to a one-player game',
        () async {
      final g = await start([p(1, 'hex', ['ctl_hex_1', 'ctl_hex_2'], game: 'g_wwe')]);
      final p1 =
          (await groupsRepo.activeGroups()).single.currentForPlayer(1)!;
      final r =
          await groups.changeGame(groupId: g.id, current: p1, gameId: 'g_gow');
      expect(r.failureOrNull?.code, 'players_exceeded');
      expect(await held(), {'ctl_hex_1', 'ctl_hex_2'});
    });

    test('switching to a system that cannot run the game is caught', () async {
      final g = await start([p(1, 'hex', ['ctl_hex_1'], game: 'g_eafc')]);
      final p1 =
          (await groupsRepo.activeGroups()).single.currentForPlayer(1)!;
      final r = await groups.switchSystem(
        groupId: g.id,
        playerNumber: 1,
        resourceId: 'ghost', // EA FC is not playable on GHOST
        resourceName: 'GHOST',
        activityCode: 'PS5',
        gameId: 'g_eafc',
        controllers: const ControllerChoice.tracked(
            requested: 1, padIds: ['ctl_ghost_1']),
        current: p1,
      );
      expect(r.failureOrNull?.code, 'not_playable');
      expect(await held(), {'ctl_hex_1'});
    });
  });
}
