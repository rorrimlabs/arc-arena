/// Two independent device databases, two accounts (owner + staff), one local
/// Supabase stack. Nothing is mocked: every op goes through sync_push and every
/// change comes back through sync_pull, applied by the real SyncApplier.
///
/// Needs the local dev stack and its URL + anon key in the environment:
///   bash tool/sync_it.sh
/// Skipped (not failed) when they are absent, so `flutter test` stays offline.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/services/group_billing.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/sim_device.dart';

void main() {
  final url = Platform.environment['AO_SUPABASE_URL'];
  final key = Platform.environment['AO_SUPABASE_ANON_KEY'];
  final skip = (url == null || key == null)
      ? 'local Supabase stack not configured (run tool/sync_it.sh)'
      : null;

  late SimDevice a; // owner's phone
  late SimDevice b; // staff tablet
  late String arenaId;

  setUpAll(() async {
    if (skip != null) return;
    final run = Random().nextInt(1 << 32).toRadixString(16);
    a = await SimDevice.signUp('A', url!, key!, 'it-owner-$run@arena.test');
    b = await SimDevice.signUp('B', url, key, 'it-staff-$run@arena.test');
    // A fresh arena per run: isolated from other runs and from the dev seed.
    arenaId = await a.client.rpc('create_arena',
        params: {'p_name': 'IT $run', 'p_owner_name': 'Owner A'}) as String;
    await a.client.rpc('add_staff_by_email', params: {
      'p_arena': arenaId,
      'p_email': 'it-staff-$run@arena.test',
      'p_name': 'Staff B',
      'p_perms': ['start', 'bill', 'discount', 'members'],
    });
    a.bind(arenaId);
    b.bind(arenaId);
  });

  tearDownAll(() async {
    if (skip != null) return;
    await a.close();
    await b.close();
  });

  Future<int> serverCount(String table, String column, String value,
      {bool openOnly = false}) async {
    var q = a.client.from(table).select('id').eq(column, value);
    if (openOnly) q = q.isFilter('ended_at', null);
    return (await q).length;
  }

  // The server re-prices every bill (0013), so money the tests send must be
  // what the app would compute: the same engine the End / Extend screens use.
  Future<EndSessionCommand> pricedEnd(SimDevice d, String id, DateTime at) async {
    final s = (await d.sessions.getById(id))!;
    final bill = const SegmentBilling().bill(
        snapshot: s.snapshot, segments: await d.sessions.segmentsFor(id), openEndAt: at);
    return EndSessionCommand(sessionId: id, actualEndedAt: at,
        charges: bill.charges, billedAmountPaise: bill.total.value);
  }

  Future<EndGroupCommand> pricedGroupEnd(SimDevice d, String id, DateTime at) async {
    final g = (await d.groups.getById(id))!;
    final bill = const GroupBilling().bill(
        snapshot: g.snapshot, assignments: await d.groups.assignmentsFor(id),
        mode: g.billingMode, purchasedControllerCount: g.purchasedControllerCount,
        groupStart: g.startedAt, openEndAt: at);
    return EndGroupCommand(groupId: id, actualEndedAt: at,
        charges: bill.charges, billedAmountPaise: bill.total.value);
  }

  // SessionPlanner.planExtension: quote to the new end − quote to the old end.
  Future<int> extensionCost(SimDevice d, Session s, DateTime newEnd) async {
    final segs = await d.sessions.segmentsFor(s.id);
    final open = segs.firstWhere((x) => x.isOpen, orElse: () => segs.last);
    int quote(DateTime end) => const PricingService()
        .quote(snapshot: s.snapshot, activityCode: open.activityCode,
            controllerCount: open.controllerCount, start: s.startedAt, end: end)
        .valueOrNull!
        .amount
        .value;
    return quote(newEnd) - quote(s.scheduledEndAt);
  }

  test('both devices start from the server catalog (shared identity)', () async {
    expect((await a.sync()).endedIn, SyncState.synced);
    expect((await b.sync()).endedIn, SyncState.synced);
    for (final d in [a, b]) {
      expect((await d.db.select(d.db.resources).get()).length, 6);
      expect((await d.db.select(d.db.controllers).get()).length, 8);
      expect((await d.db.select(d.db.rates).get()).length, 12);
      expect((await d.db.select(d.db.users).get()).length, 2);
    }
    expect(await a.station('HEX'), await b.station('HEX'),
        reason: 'one id per station on every device');
    final staff = await (b.db.select(b.db.users)
          ..where((t) => t.id.equals(b.userId)))
        .getSingle();
    expect(staff.perms.toSet(), {'start', 'bill', 'discount', 'members'});
  }, skip: skip);

  late String ravi;

  test('critical scenario: HEX holds VOID-1/2; VOID borrows from GHOST on '
      'another device', () async {
    ravi = (await a.customers.create(name: 'Ravi', phone: '98${DateTime.now().microsecond}1')).id;
    final hex = await a.start(
      customerId: ravi,
      stationName: 'HEX',
      padLabels: ['HEX-1', 'HEX-2', 'VOID-1', 'VOID-2'],
      borrowLabels: ['VOID-1', 'VOID-2'],
    );
    expect(hex.isOk, isTrue, reason: '${hex.failureOrNull?.message}');
    final pushed = await a.sync();
    expect(pushed.applied, 2, reason: 'customer.create + session.start');
    expect(pushed.rejected, 0);
    expect(await serverCount('controller_allocations', 'session_id',
        hex.valueOrNull!.id, openOnly: true), 4);

    // Device B learns about it through the pull alone.
    await b.sync();
    expect(await b.openPadLabels(), {'HEX-1', 'HEX-2', 'VOID-1', 'VOID-2'});
    final void1 = await (b.db.select(b.db.controllers)
          ..where((t) => t.label.equals('VOID-1')))
        .getSingle();
    expect(void1.currentResourceId, await b.station('HEX'),
        reason: 'the borrow (location) synced too');

    // A new customer wants VOID: VOID-1/2 cannot be taken again — refused
    // on the device before anything is written.
    final walkIn = (await b.customers.createGuest()).id;
    final reuse = await b.start(
        customerId: walkIn, stationName: 'VOID', padLabels: ['VOID-1', 'VOID-2']);
    expect(reuse.isErr, isTrue);
    expect(reuse.failureOrNull!.code, anyOf('controller_elsewhere', 'controller_taken'));
    // Count-only: VOID has no free pads.
    final countOnly = await b.start(
        customerId: walkIn, stationName: 'VOID', padLabels: const [], count: 2);
    expect(countOnly.failureOrNull?.code, 'controllers_unavailable');

    // Borrowing GHOST's pads works, on B, and the server agrees.
    final onVoid = await b.start(
      customerId: walkIn,
      stationName: 'VOID',
      padLabels: ['GHOST-1', 'GHOST-2'],
      borrowLabels: ['GHOST-1', 'GHOST-2'],
    );
    expect(onVoid.isOk, isTrue, reason: '${onVoid.failureOrNull?.message}');
    final bPush = await b.sync();
    expect(bPush.rejected, 0);
    expect(await serverCount('controller_moves', 'session_ref',
        's:${onVoid.valueOrNull!.id}'), 2);

    await a.sync();
    expect(await a.openPadLabels(),
        {'HEX-1', 'HEX-2', 'VOID-1', 'VOID-2', 'GHOST-1', 'GHOST-2'},
        reason: 'A sees B\'s session and pads');
  }, skip: skip);

  test('offline conflict: both devices take RIFT; the second is refused, '
      'rolled back, and kept for attention — money included', () async {
    final x = (await a.customers.createGuest()).id;
    final y = (await b.customers.createGuest()).id;
    // Neither device syncs: each believes RIFT and RIFT-1 are free.
    final onA = await a.start(customerId: x, stationName: 'RIFT', padLabels: ['RIFT-1']);
    final onB = await b.start(customerId: y, stationName: 'RIFT', padLabels: ['RIFT-1']);
    expect(onA.isOk && onB.isOk, isTrue);
    final bSession = onB.valueOrNull!.id;
    await b.sessions.recordPayment(RecordPaymentCommand(
        sessionId: bSession, amountPaise: 15000, method: PaymentMethod.cash));

    expect((await a.sync()).rejected, 0, reason: 'A reaches the server first');
    final report = await b.sync();
    expect(report.rejected, 2, reason: 'B\'s start and its payment are refused');
    expect(report.rolledBack, greaterThanOrEqualTo(2));

    // B converged on the server: its RIFT session is gone, A's is there.
    expect(await b.sessions.getById(bSession), isNull);
    expect((await b.sessions.getById(onA.valueOrNull!.id))?.isActive, isTrue);
    expect(await b.openPadLabels(), contains('RIFT-1'));
    expect(await b.sessions.paymentsFor(bSession), isEmpty);
    // …but nothing is lost: the refused ops (with the ₹150) await a person.
    final refused = await b.outbox(OutboxStatus.rejected);
    expect({for (final o in refused) o.kind}, {'session.start', 'payment.record'});
    expect(refused.firstWhere((o) => o.kind == 'session.start').errorCode,
        anyOf('resource_busy', 'controller_taken'));
    expect(refused.firstWhere((o) => o.kind == 'payment.record').payload,
        contains('15000'));
    expect(b.engine.status.needsAttention, 2);
    expect(await serverCount('sessions', 'id', bSession), 0);
  }, skip: skip);

  test('a payment retried after a lost response is recorded once', () async {
    final s = (await a.sessions.active()).first.session.id;
    final pay = await a.sessions.recordPayment(RecordPaymentCommand(
        sessionId: s, amountPaise: 5000, method: PaymentMethod.upi));
    final op = (await a.outbox(OutboxStatus.pending)).single;
    // The push reaches the server, but the device never hears back.
    final first = await a.transport.push(arenaId, [
      (
        opId: op.opId,
        kind: op.kind,
        payload: jsonDecode(op.payload) as Map<String, dynamic>,
      ),
    ], 'lost-response');
    expect(first.single.status, 'applied');
    expect((await a.outbox(OutboxStatus.pending)).single.opId, op.opId,
        reason: 'the device still thinks it is pending');
    // Its next pass sends it again: the server replays, never re-applies.
    final again = await a.sync();
    expect(again.applied, 1);
    expect(await a.outbox(OutboxStatus.pending), isEmpty);
    expect(await serverCount('payments', 'id', pay.valueOrNull!.id), 1);
    expect(await serverCount('payments', 'session_id', s), 1);
  }, skip: skip);

  test('a stale end (priced before another device extended) is refused and '
      'the device rolls forward to the server', () async {
    await a.sync();
    await b.sync();
    final target = (await b.sessions.active())
        .firstWhere((x) => x.segments.any((s) => s.isOpen && s.resourceId.isNotEmpty))
        .session;
    // A extends and syncs; B, not having pulled, ends from the old end.
    final newEnd = target.scheduledEndAt.add(const Duration(minutes: 30));
    final ext = await a.sessions.extend(ExtendSessionCommand(
      sessionId: target.id,
      addedMinutes: 30,
      newEndAt: newEnd,
      addedAmountPaise: await extensionCost(a, target, newEnd),
    ));
    expect(ext.isOk, isTrue);
    await a.sync();
    final ended = await b.sessions
        .end(await pricedEnd(b, target.id, DateTime.now().toUtc()));
    expect(ended.valueOrNull?.status, SessionStatus.completed);
    final r = await b.sync();
    expect(r.rejected, 1);
    final refused = (await b.outbox(OutboxStatus.rejected))
        .firstWhere((o) => o.kind == 'session.end');
    expect(refused.errorCode, 'stale');
    final now = await b.sessions.getById(target.id);
    expect(now!.isActive, isTrue, reason: 'rolled back to the server: still running');
    expect(now.scheduledEndAt, target.scheduledEndAt.add(const Duration(minutes: 30)));
    expect(await b.sessions.chargesFor(target.id), isEmpty,
        reason: 'the refused bill\'s charges are gone');
    expect((await b.sessions.segmentsFor(target.id)).where((s) => s.isOpen),
        hasLength(1), reason: 'its station is held again on this device');
    final reopened = await (b.db.select(b.db.controllerAllocations)
          ..where((t) => t.sessionId.equals(target.id) & t.endedAt.isNull()))
        .get();
    expect(reopened, isNotEmpty,
        reason: 'the pads the refused end released are held again');
  }, skip: skip);

  test('staff cannot change prices: refused by the server, device reverts',
      () async {
    await b.catalog.upsertRate(Rate(
      activityCode: 'PS5',
      band: Band.standard,
      controllerCount: 1,
      unitMinutes: 60,
      price: const Paise(100),
    ));
    final r = await b.sync();
    expect(r.rejected, 1);
    expect((await b.outbox(OutboxStatus.rejected)).last.errorCode, 'forbidden');
    final price = (await b.catalog.rates()).firstWhere((x) =>
        x.activityCode == 'PS5' && x.band == Band.standard && x.controllerCount == 1);
    expect(price.price.value, 15000, reason: 'reverted to the server price');
  }, skip: skip);

  test('the owner can, and the other device gets it', () async {
    await a.catalog.upsertRate(Rate(
      activityCode: 'PS5',
      band: Band.standard,
      controllerCount: 1,
      unitMinutes: 60,
      price: const Paise(16000),
    ));
    expect((await a.sync()).rejected, 0);
    await b.sync();
    final price = (await b.catalog.rates()).where((x) =>
        x.activityCode == 'PS5' && x.band == Band.standard && x.controllerCount == 1);
    expect(price.single.price.value, 16000, reason: 'one row, the new price');
  }, skip: skip);

  test('ops survive a restart: a new engine on the same database sends them',
      () async {
    final g = (await b.customers.createGuest()).id;
    expect((await b.outbox(OutboxStatus.pending)).length, 1);
    await b.engine.dispose(); // "app killed" before it could sync
    final engine2 = SyncEngine(db: b.db, transport: b.transport, arenaId: arenaId);
    final r = await engine2.syncNow();
    expect(r.applied, 1);
    expect(await serverCount('customers', 'id', g), 1);
    await engine2.dispose();
    b.engine = engine2; // so tearDown disposes something valid
  }, skip: skip);

  test('ending a session on one device frees its pads on the other', () async {
    await a.sync();
    final hex = await a.station('HEX');
    final hexSession = (await a.sessions.active())
        .firstWhere((x) => x.segments.any((s) => s.isOpen && s.resourceId == hex))
        .session;
    // Ended 47m13.517s in: a real, multi-paise bill the server must re-price.
    final res = await a.sessions.end(await pricedEnd(a, hexSession.id,
        hexSession.startedAt.add(const Duration(minutes: 47, seconds: 13, milliseconds: 517))));
    expect(res.isOk, isTrue);
    expect((await a.sync()).rejected, 0);
    expect(await serverCount('controller_allocations', 'session_id', hexSession.id,
        openOnly: true), 0);
    await b.sync();
    final stillOpen = await (b.db.select(b.db.controllerAllocations)
          ..where((t) => t.sessionId.equals(hexSession.id) & t.endedAt.isNull()))
        .get();
    expect(stillOpen, isEmpty);
    final history = await (b.db.select(b.db.controllerAllocations)
          ..where((t) => t.sessionId.equals(hexSession.id)))
        .get();
    expect(history, isNotEmpty, reason: 'allocation history is kept');
  }, skip: skip);

  test('a group with tracked pads syncs, and ending it on the other device '
      'releases them', () async {
    await a.sync();
    await b.sync();

    final now = DateTime.now().toUtc();
    final eafc = await b.game('EA SPORTS FC 25');
    final hex = await b.station('HEX');
    final created = await b.groups.create(CreateGroupCommand(
      primaryCustomerId: (await b.customers.createGuest()).id,
      playerCount: 2,
      purchasedControllerCount: 2,
      startedAt: now,
      scheduledEndAt: now.add(const Duration(hours: 1)),
      snapshot: await b.catalog.currentSnapshot(),
      billingMode: GroupBillingMode.perSystem,
      assignments: [
        for (final (n, label) in [(1, 'HEX-1'), (2, 'HEX-2')])
          GroupAssignmentDraft(
            playerNumber: n,
            resourceId: hex,
            resourceName: 'HEX',
            activityCode: 'PS5',
            gameId: eafc,
            controllerCount: 1,
            controllerIds: [await b.pad(label)],
          ),
      ],
    ));
    expect(created.isOk, isTrue, reason: '${created.failureOrNull?.message}');
    expect((await b.sync()).rejected, 0);
    final groupId = created.valueOrNull!.id;
    expect(await serverCount('controller_allocations', 'group_id', groupId,
        openOnly: true), 2);

    await a.sync();
    final group = await a.groups.getById(groupId);
    expect(group?.isActive, isTrue);
    final ended = await a.groups.end(await pricedGroupEnd(a, groupId,
        group!.startedAt.add(const Duration(minutes: 47, seconds: 13, milliseconds: 517))));
    expect(ended.isOk, isTrue);
    expect((await a.sync()).rejected, 0);
    await b.sync();
    expect((await b.groups.getById(groupId))?.status, GroupSessionStatus.completed);
    expect(await b.openPadLabels(), isNot(contains('HEX-1')));
  }, skip: skip);

  test('two devices checking in the same booking offline: one session, one '
      'check-in', () async {
    final start = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final booking = await a.bookings.create(Booking(
      id: '',
      customerId: ravi,
      activityCode: 'POOL',
      resourceId: await a.station('Pool Table 1'),
      scheduledStart: start,
      scheduledEnd: start.add(const Duration(hours: 1)),
      status: BookingStatus.booked,
      createdAt: start,
      updatedAt: start,
    ));
    await a.sync();
    await b.sync();
    Future<Result<Session>> checkIn(SimDevice d) async {
      final now = DateTime.now().toUtc();
      return d.sessions.start(StartSessionCommand(
        customerId: ravi,
        startedAt: now,
        scheduledEndAt: now.add(const Duration(hours: 1)),
        snapshot: await d.catalog.currentSnapshot(),
        resourceId: await d.station('Pool Table 1'),
        resourceName: 'Pool Table 1',
        activityCode: 'POOL',
        bookingId: booking.id,
      ));
    }

    final onA = await checkIn(a);
    final onB = await checkIn(b);
    expect(onA.isOk && onB.isOk, isTrue, reason: 'both believe it is open');
    expect((await a.sync()).rejected, 0);
    expect((await b.sync()).rejected, 1);
    final refused = (await b.outbox(OutboxStatus.rejected)).last;
    expect(refused.errorCode, anyOf('booking_not_open', 'resource_busy'));
    expect(await b.sessions.getById(onB.valueOrNull!.id), isNull);
    expect((await b.bookings.getById(booking.id))!.status, BookingStatus.checkedIn);
    expect(await serverCount('sessions', 'booking_id', booking.id), 1);
  }, skip: skip);

  test('two ONLINE devices grab the same pad at the same moment: the server '
      'serialises them, exactly one holds it, both converge', () async {
    await a.sync();
    await b.sync();
    // VOID-1 stands at HEX (borrowed earlier), free since HEX ended.
    final onA = await a.start(
        customerId: ravi,
        stationName: 'GHOST',
        gameName: 'Tekken 8',
        padLabels: ['VOID-1'],
        borrowLabels: ['VOID-1']);
    final onB = await b.start(
        customerId: ravi, stationName: 'HEX', padLabels: ['VOID-1']);
    expect(onA.isOk && onB.isOk, isTrue,
        reason: '${onA.failureOrNull?.message} ${onB.failureOrNull?.message}');
    final results = await Future.wait([a.sync(), b.sync()]);
    expect(results[0].rejected + results[1].rejected, 1,
        reason: 'exactly one of the two is refused');
    final void1 = await a.pad('VOID-1');
    expect(await serverCount('controller_allocations', 'controller_id', void1,
        openOnly: true), 1);
    await a.sync();
    await b.sync();
    expect(await a.openPadLabels(), await b.openPadLabels(),
        reason: 'both devices agree who holds which pad');
  }, skip: skip);

  test('turning a member off stops their device syncing; their unsent work '
      'stays on the device', () async {
    await b.sync();
    final staff = await (a.db.select(a.db.users)..where((t) => t.id.equals(b.userId)))
        .getSingle();
    await LocalUserRepository(a.db, a.clock, a.recorder).upsert(AppUser(
      id: staff.id,
      name: staff.name,
      perms: Permission.parse(staff.perms),
      active: false,
    ));
    expect((await a.sync()).rejected, 0);
    await b.customers.createGuest();
    final r = await b.sync();
    expect(r.endedIn, SyncState.authProblem);
    expect(b.engine.status.accessRevoked, isTrue);
    expect((await b.outbox(OutboxStatus.pending)).length, 1,
        reason: 'nothing is thrown away');
  }, skip: skip);
}
