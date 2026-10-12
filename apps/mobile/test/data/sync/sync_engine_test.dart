/// The outbox and the sync engine without a server: a scripted transport plays
/// the server's part, so offline / retry / refusal / restart paths are exact.
/// (The same flows against a real server: test/sync/two_device_sync_test.dart.)
library;

import 'dart:convert';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/sync/sync_applier.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_transport.dart';
import '../../support/test_db.dart';

void main() {
  late AppDatabase db;
  late ScriptedTransport server;
  late SyncRecorder recorder;
  late LocalSessionRepository sessions;
  late LocalCustomerRepository customers;
  late SyncEngine engine;
  final clock = FakeClock(DateTime.utc(2026, 10, 11, 10));

  setUp(() async {
    db = await seededMemoryDb();
    server = ScriptedTransport();
    recorder = SyncRecorder(db, actor: () => 'u1', clock: clock);
    sessions = LocalSessionRepository(db, clock, recorder);
    customers = LocalCustomerRepository(db, clock, recorder);
    engine = SyncEngine(db: db, transport: server, arenaId: 'arena', clock: clock);
  });
  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  Future<String> startAtVoidBorrowingGhost() async {
    final who = await customers.create(name: 'Ravi');
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: clock.now(),
      scheduledEndAt: clock.now().add(const Duration(hours: 1)),
      snapshot: await LocalCatalogRepository(db).currentSnapshot(),
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      gameId: 'g_eafc',
      controllerCount: 3,
      controllerIds: ['ctl_void_1', 'ctl_void_2', 'ctl_ghost_1'],
      borrowControllerIds: ['ctl_ghost_1'],
    ));
    expect(started.isOk, isTrue, reason: '${started.failureOrNull?.message}');
    return started.valueOrNull!.id;
  }

  Future<List<SyncOutboxRow>> outbox() =>
      (db.select(db.syncOutbox)..orderBy([(t) => OrderingTerm(expression: t.seq)])).get();

  group('recording', () {
    test('a start records ONE op carrying every id the device generated',
        () async {
      final id = await startAtVoidBorrowingGhost();
      final ops = await outbox();
      expect([for (final o in ops) o.kind], ['customer.create', 'session.start']);
      final p = jsonDecode(ops.last.payload) as Map<String, dynamic>;
      expect(p['id'], id);
      final seg = (await sessions.segmentsFor(id)).single;
      expect(p['segment_id'], seg.id);
      final allocs = await (db.select(db.controllerAllocations)
            ..where((t) => t.sessionId.equals(id)))
          .get();
      expect({for (final a in p['allocations'] as List) (a as Map)['id']},
          {for (final a in allocs) a.id},
          reason: 'server will reuse the device allocation ids');
      final move = (await db.select(db.controllerMoves).get()).single;
      expect(p['moves'], [
        {'id': move.id, 'controller_id': 'ctl_ghost_1'}
      ]);
      expect(ops.last.status, OutboxStatus.pending);
      expect(ops.last.actorId, 'u1');
    });

    test('a refused local op records nothing (same transaction)', () async {
      await startAtVoidBorrowingGhost();
      final before = (await outbox()).length;
      final again = await sessions.start(StartSessionCommand(
        customerId: (await customers.createGuest()).id,
        startedAt: clock.now(),
        scheduledEndAt: clock.now().add(const Duration(hours: 1)),
        snapshot: await LocalCatalogRepository(db).currentSnapshot(),
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
      ));
      expect(again.isErr, isTrue);
      expect((await outbox()).length, before + 1,
          reason: 'only the guest customer; no op for the refused start');
    });

    test('end carries what the bill was priced from (stale guard)', () async {
      final id = await startAtVoidBorrowingGhost();
      await sessions.end(EndSessionCommand(
        sessionId: id,
        actualEndedAt: clock.now().add(const Duration(minutes: 30)),
        charges: const [],
        billedAmountPaise: 19500,
      ));
      final p = jsonDecode((await outbox()).last.payload) as Map<String, dynamic>;
      expect(p['expected_segment_ids'],
          [for (final s in await sessions.segmentsFor(id)) s.id]);
      expect(p['expected_scheduled_end_at'],
          clock.now().add(const Duration(hours: 1)).toIso8601String());
    });

    test('local-only repositories (no recorder) never touch the outbox', () async {
      final plain = LocalSessionRepository(db, clock);
      final who = await LocalCustomerRepository(db, clock).create(name: 'X');
      await plain.start(StartSessionCommand(
        customerId: who.id,
        startedAt: clock.now(),
        scheduledEndAt: clock.now().add(const Duration(hours: 1)),
        snapshot: await LocalCatalogRepository(db).currentSnapshot(),
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      expect(await outbox(), isEmpty);
    });
  });

  group('pushing', () {
    test('offline: ops stay pending, nothing is pulled, status says offline; '
        'they go when the server is back', () async {
      await startAtVoidBorrowingGhost();
      server.pushThrows = SyncOfflineException('no route');
      final r = await engine.syncNow();
      expect(r.endedIn, SyncState.offline);
      expect(engine.status.state, SyncState.offline);
      expect(engine.status.pending, 2);
      expect(server.pulls, 0);
      expect((await outbox()).every((o) => o.attempts == 1), isTrue);

      server.pushThrows = null;
      final r2 = await engine.syncNow();
      expect(r2.applied, 2);
      expect(engine.status.state, SyncState.synced);
      expect(engine.status.pending, 0);
    });

    test('a transient "retry" keeps that op and everything after it pending, '
        'in order, and withholds the pull', () async {
      await startAtVoidBorrowingGhost();
      server.onPush = (o) => o.kind == 'session.start'
          ? OpResult(opId: o.opId, status: 'retry', error: '40001')
          : OpResult(opId: o.opId, status: 'applied');
      final r = await engine.syncNow();
      expect(r.applied, 1);
      final ops = await outbox();
      expect(ops.first.status, OutboxStatus.applied);
      expect(ops.last.status, OutboxStatus.pending);
      expect(server.pulls, 0,
          reason: 'never lay server rows over an unsent local change');
      expect(engine.status.state, SyncState.pending);
    });

    test('a replayed answer (lost response, re-sent op) is recorded once',
        () async {
      await customers.createGuest();
      server.onPush =
          (o) => OpResult(opId: o.opId, status: 'applied', replayed: true);
      await engine.syncNow();
      await engine.syncNow();
      expect(server.pushed.length, 1, reason: 'applied ops are never re-sent');
      expect((await outbox()).single.status, OutboxStatus.applied);
    });

    test('revoked access stops syncing and keeps every op', () async {
      await customers.createGuest();
      server.pushThrows = SyncAuthException('not a member', revoked: true);
      final r = await engine.syncNow();
      expect(r.endedIn, SyncState.authProblem);
      expect(engine.status.accessRevoked, isTrue);
      expect((await outbox()).single.status, OutboxStatus.pending);
    });

    test('a change is pushed right after it is written (the nudge fires from '
        'inside the write transaction)', () async {
      final nudging = SyncRecorder(db, actor: () => 'u1', clock: clock,
          onRecorded: engine.nudge);
      await LocalCustomerRepository(db, clock, nudging).createGuest();
      await engine.statusStream
          .firstWhere((s) => s.state == SyncState.synced)
          .timeout(const Duration(seconds: 3));
      expect(server.pushed.single.kind, 'customer.create');
      expect((await outbox()).single.status, OutboxStatus.applied);
    });

    test('after the sign-in expires, new changes are still counted as waiting '
        '(the sign-out warning depends on it)', () async {
      await customers.createGuest();
      server.pushThrows = SyncAuthException('JWT expired');
      expect((await engine.syncNow()).endedIn, SyncState.authProblem);
      expect(engine.status.pending, 1);
      final nudging = SyncRecorder(db, actor: () => 'u1', clock: clock,
          onRecorded: engine.nudge);
      await LocalCustomerRepository(db, clock, nudging).createGuest();
      await engine.statusStream.firstWhere((s) => s.pending == 2)
          .timeout(const Duration(seconds: 2));
      expect(engine.status.state, SyncState.authProblem);
      expect(engine.status.pending, 2);
      expect(server.pushed, isEmpty, reason: 'nothing is sent while stopped');
    });

    test('ops written before a restart are sent by the next engine', () async {
      await customers.createGuest();
      await engine.dispose();
      engine = SyncEngine(db: db, transport: server, arenaId: 'arena', clock: clock);
      expect((await engine.syncNow()).applied, 1);
    });
  });

  group('rolling back a refusal', () {
    test('a refused start is undone on the device: session, segment, pads, '
        'borrow, payment — and the ops are kept for a person', () async {
      final id = await startAtVoidBorrowingGhost();
      await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 15000, method: PaymentMethod.cash));
      server.onPush = (o) => o.kind == 'customer.create'
          ? OpResult(opId: o.opId, status: 'applied')
          : OpResult(opId: o.opId, status: 'rejected', error: 'resource_busy');
      // The server never had the session; GHOST-1 is still at GHOST there.
      final ghost1 = await (db.select(db.controllers)
            ..where((t) => t.id.equals('ctl_ghost_1')))
          .getSingle();
      server.entities = [
        (
          type: 'controller',
          id: 'ctl_ghost_1',
          rows: [
            {
              't': 'controllers',
              'r': {
                'id': 'ctl_ghost_1',
                'label': ghost1.label,
                'home_resource_id': 'ghost',
                'current_resource_id': 'ghost',
                'status': 'usable',
                'notes': null,
                'loan_return_to': null,
                'loan_session_ref': null,
                'updated_at': clock.now().toIso8601String(),
              },
            },
          ],
        ),
      ];
      final r = await engine.syncNow();
      expect(r.rejected, 2);
      expect(await sessions.getById(id), isNull);
      expect(await sessions.paymentsFor(id), isEmpty);
      expect(await db.select(db.controllerAllocations).get(), isEmpty);
      expect(await db.select(db.controllerMoves).get(), isEmpty);
      final pad = await (db.select(db.controllers)
            ..where((t) => t.id.equals('ctl_ghost_1')))
          .getSingle();
      expect(pad.currentResourceId, 'ghost');
      expect(pad.loanReturnTo, isNull,
          reason: 'a server null clears the local loan');
      final kept = await (db.select(db.syncOutbox)
            ..where((t) => t.status.equals(OutboxStatus.rejected)))
          .get();
      expect(kept.length, 2);
      expect(kept.every((o) => !o.needsRefetch), isTrue);
      expect(engine.status.needsAttention, 2);
      await engine.acknowledge(kept.first.opId);
      expect(engine.status.needsAttention, 1);
    });
  });

  group('rolling back a refused check-in', () {
    test('the booking returns to the server\'s status (not stuck checked in)',
        () async {
      final bookings = LocalBookingRepository(db, clock, recorder);
      final who = await customers.create(name: 'Asha');
      final start = clock.now().add(const Duration(minutes: 5));
      final booking = await bookings.create(Booking(
        id: '',
        customerId: who.id,
        activityCode: 'POOL',
        resourceId: 'pool1',
        scheduledStart: start,
        scheduledEnd: start.add(const Duration(hours: 1)),
        status: BookingStatus.booked,
        createdAt: clock.now(),
        updatedAt: clock.now(),
      ));
      final stored = (await db.select(db.bookings).get()).single;
      final started = await sessions.start(StartSessionCommand(
        customerId: who.id,
        startedAt: clock.now(),
        scheduledEndAt: clock.now().add(const Duration(hours: 1)),
        snapshot: await LocalCatalogRepository(db).currentSnapshot(),
        resourceId: 'pool1',
        resourceName: 'Pool Table 1',
        activityCode: 'POOL',
        bookingId: booking.id,
      ));
      expect(started.isOk, isTrue, reason: '${started.failureOrNull?.message}');
      expect((await bookings.getById(booking.id))!.status, BookingStatus.checkedIn);

      // Another device took the table first: the server keeps the booking open.
      server.onPush = (o) => o.kind == 'session.start'
          ? OpResult(opId: o.opId, status: 'rejected', error: 'resource_busy')
          : OpResult(opId: o.opId, status: 'applied');
      server.entities = [
        (
          type: 'booking',
          id: booking.id,
          rows: [
            {
              't': 'bookings',
              'r': {
                'id': booking.id,
                'customer_id': who.id,
                'activity_code': 'POOL',
                'game_id': null,
                'resource_id': 'pool1',
                'scheduled_start': stored.scheduledStart.toIso8601String(),
                'scheduled_end': stored.scheduledEnd.toIso8601String(),
                'players_required': null,
                'controller_requirement': null,
                'status': 'booked',
                'party_name': null,
                'phone': null,
                'notes': null,
                'reminder_status': 'none',
                'created_at': stored.createdAt.toIso8601String(),
                'updated_at': stored.updatedAt.toIso8601String(),
              },
            },
          ],
        ),
      ];
      final r = await engine.syncNow();
      expect(r.rejected, 1);
      expect(await sessions.getById(started.valueOrNull!.id), isNull);
      expect((await bookings.getById(booking.id))!.status, BookingStatus.booked);
    });
  });

  group('applying server rows', () {
    // game.replace_controls deletes a game's controls and re-inserts them,
    // keeping the ids of unchanged ones, in ONE transaction: the page carries
    // the live row and its tombstone, in no particular order.
    test('a row the server still has survives its own tombstone in the page',
        () async {
      final game = (await db.select(db.games).get()).first.id;
      final control = {
        'id': 'ctl-row-1',
        'game_id': game,
        'section': 'Basics',
        'action': 'Shoot',
        'buttons': ['R2'],
        'explanation': null,
        'notes': null,
        'image_url': null,
        'sort_order': 0,
      };
      Map<String, dynamic> tomb(String table, Map<String, dynamic> row) =>
          {'t': '_tombstone', 'r': {'table': table, 'row': row}};
      await db.transaction(() => SyncApplier(db).applyChanges([
            {'t': 'game_controls', 'r': control},
            tomb('game_controls', {...control, 'action': 'Old'}),
            tomb('holidays', {'day': '2026-12-25', 'name': 'Xmas', 'closed': true}),
            {'t': 'holidays', 'r': {'day': '2026-12-25', 'name': 'Xmas', 'closed': true}},
            tomb('holidays', {'day': '2026-12-31', 'name': 'NYE', 'closed': true}),
          ]));
      final controls = await (db.select(db.gameControls)
            ..where((t) => t.id.equals('ctl-row-1')))
          .get();
      expect(controls.single.action, 'Shoot');
      final days = {for (final h in await db.select(db.holidays).get()) h.day};
      expect(days, contains('2026-12-25'), reason: 're-added: still there');
      expect(days, isNot(contains('2026-12-31')), reason: 'a real delete applies');
    });

    test('a server null overwrites the device value (re-opened segment)',
        () async {
      final id = await startAtVoidBorrowingGhost();
      final seg = (await sessions.segmentsFor(id)).single;
      await (db.update(db.sessionSegments)..where((t) => t.id.equals(seg.id)))
          .write(SessionSegmentsCompanion(endedAt: Value(clock.now())));
      await db.transaction(() => SyncApplier(db).upsert('session_segments', {
            'id': seg.id,
            'session_id': id,
            'idx': 0,
            'resource_id': 'void',
            'activity_code': 'PS5',
            'game_id': 'g_eafc',
            'controller_count': 3,
            'started_at': seg.startedAt.toIso8601String(),
            'ended_at': null,
            'created_at': clock.now().toIso8601String(),
          }));
      expect((await sessions.segmentsFor(id)).single.isOpen, isTrue);
    });

    test('a pulled open segment provisionally closes a stale open one on the '
        'same station, so the one-open index holds', () async {
      final id = await startAtVoidBorrowingGhost();
      await db.transaction(() => SyncApplier(db).applyChanges([
            {
              't': 'session_segments',
              'r': {
                'id': 'other-seg',
                'session_id': 'other-session',
                'idx': 0,
                'resource_id': 'void',
                'activity_code': 'PS5',
                'game_id': null,
                'controller_count': null,
                'started_at': clock.now().add(const Duration(minutes: 5)).toIso8601String(),
                'ended_at': null,
                'created_at': clock.now().toIso8601String(),
              },
            },
          ]));
      final open = await sessions.openSegments();
      expect(open.where((s) => s.resourceId == 'void').single.id, 'other-seg');
      expect((await sessions.segmentsFor(id)).single.isOpen, isFalse);
    });

    test('device-local columns survive a pull: PIN hash, booking reminder',
        () async {
      final before = await (db.select(db.users)..where((t) => t.id.equals('u1')))
          .getSingle();
      await db.transaction(() => SyncApplier(db).upsert('staff_profiles', {
            'user_id': 'u1',
            'name': 'Renamed',
            'perms': ['start'],
            'active': true,
            'sort_order': 1,
          }));
      final after = await (db.select(db.users)..where((t) => t.id.equals('u1')))
          .getSingle();
      expect(after.name, 'Renamed');
      expect(after.perms, ['start']);
      expect(after.pinHash, before.pinHash);
      expect(after.pinSalt, before.pinSalt);
    });

    test('settings that are device-local are never synced', () async {
      await db.into(db.settings).insert(
          SettingsCompanion.insert(key: 'notifications', json: '{"on":true}'));
      await db.transaction(() => SyncApplier(db).applyChanges([
            {
              't': 'settings',
              'r': {'key': 'notifications', 'json': {'on': false}},
            },
            {
              't': '_tombstone',
              'r': {'table': 'settings', 'row': {'key': 'notifications'}},
            },
          ]));
      final row = await (db.select(db.settings)
            ..where((t) => t.key.equals('notifications')))
          .getSingle();
      expect(row.json, '{"on":true}');
    });
  });
}
