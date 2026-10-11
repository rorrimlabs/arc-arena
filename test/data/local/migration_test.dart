/// Schema migrations: every step must carry the centre's records forward.
///
/// Each case builds a database in the *old* shape, writes real business rows
/// into it, then opens it with the current [AppDatabase] and asserts that the
/// rows are still there and still correct.
library;

import 'dart:io';

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_controller_allocation_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/repositories/user_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late File file;
  final start = DateTime.utc(2026, 10, 10, 9);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('arena_ops_migration');
    file = File('${dir.path}/arena.sqlite');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Builds a genuine **v10** database holding one session, one segment and one
  /// payment, plus two staff accounts with plaintext PINs.
  ///
  /// v11's only schema change is to `users`, so a faithful v10 file is the
  /// current schema with exactly that change reversed: the plaintext `pin`
  /// column back, the salt/hash/lockout columns gone, `user_version` at 10.
  Future<String> buildV10Database() async {
    final db = AppDatabase(NativeDatabase(file));
    await LocalSeed.apply(db);
    final catalog = LocalCatalogRepository(db);
    final customers = LocalCustomerRepository(db);
    final sessions = LocalSessionRepository(db);
    final snapshot = await catalog.currentSnapshot();
    final who = await customers.create(name: 'Ravi');
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: start,
      scheduledEndAt: start.add(const Duration(hours: 1)),
      snapshot: snapshot,
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 2,
    ));
    final sessionId = started.valueOrNull!.id;
    await sessions.recordPayment(RecordPaymentCommand(
      sessionId: sessionId,
      amountPaise: 60700,
      method: PaymentMethod.cash,
    ));
    await db.close();

    // Reverse the v11 users change.
    final raw = sqlite3.open(file.path);
    raw.execute('ALTER TABLE users ADD COLUMN pin TEXT NOT NULL DEFAULT ""');
    raw.execute("UPDATE users SET pin = '1111' WHERE id = 'u1'");
    raw.execute("UPDATE users SET pin = '2222' WHERE id = 'u2'");
    for (final column in const [
      'pin_salt',
      'pin_hash',
      'pin_iterations',
      'failed_attempts',
      'locked_until_at',
    ]) {
      raw.execute('ALTER TABLE users DROP COLUMN $column');
    }
    // Reverse the v11 -> v12 additions too, so the fixture is a faithful v10
    // file (the current AppDatabase builds the v12 shape via createAll).
    raw.execute('DROP TABLE IF EXISTS controller_moves');
    raw.execute('DROP TABLE IF EXISTS controller_allocations');
    raw.execute('ALTER TABLE resources DROP COLUMN current_mode');
    raw.execute('PRAGMA user_version = 10');
    raw.close();
    return sessionId;
  }

  test('the v10 fixture really is at v10, with a plaintext PIN column', () async {
    await buildV10Database();
    final raw = sqlite3.open(file.path);
    expect(raw.userVersion, 10);
    final columns = raw
        .select("SELECT name FROM pragma_table_info('users')")
        .map((r) => '${r['name']}')
        .toSet();
    expect(columns, contains('pin'));
    expect(columns, isNot(contains('pin_hash')));
    expect(
      raw.select("SELECT pin FROM users WHERE id = 'u1'").first['pin'],
      '1111',
      reason: 'the fixture must reproduce the flaw the migration fixes',
    );
    raw.close();
  });

  group('v10 -> v11 (PINs stop being stored in the clear)', () {
    test('sessions, segments and payments survive the migration', () async {
      final sessionId = await buildV10Database();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final sessions = LocalSessionRepository(db);

      expect(db.rebuiltFromVersion, 0,
          reason: 'this must be a sequential step, not a rebuild');

      final reloaded = await sessions.getById(sessionId);
      expect(reloaded, isNotNull);
      expect(reloaded!.startedAt, start);
      expect(reloaded.scheduledEndAt, start.add(const Duration(hours: 1)));
      expect(reloaded.status, SessionStatus.active);
      expect((await sessions.paymentsFor(sessionId)).single.amountPaise, 60700);
      final segment = (await sessions.segmentsFor(sessionId)).single;
      expect(segment.resourceId, 'hex');
      expect(segment.controllerCount, 2);
      // The floor still shows the station as occupied after the upgrade.
      expect((await sessions.openSegments()).single.resourceId, 'hex');
    });

    test('the PINs staff already know keep working, now hashed', () async {
      await buildV10Database();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final users = LocalUserRepository(db);

      // Converted in place, not reset: staff are not locked out by an upgrade.
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
      expect(await users.verify('u2', '2222'), isA<PinAccepted>());
      expect(await users.verify('u1', '2222'), isA<PinRejected>());
    });

    test('no plaintext PIN is left anywhere in the file', () async {
      await buildV10Database();

      final db = AppDatabase(NativeDatabase(file));
      final users = LocalUserRepository(db);
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
      await db.close();

      final raw = sqlite3.open(file.path);
      final columns = raw
          .select("SELECT name FROM pragma_table_info('users')")
          .map((r) => '${r['name']}')
          .toSet();
      expect(columns, isNot(contains('pin')));
      expect(columns, containsAll(<String>[
        'pin_salt',
        'pin_hash',
        'pin_iterations',
        'failed_attempts',
        'locked_until_at',
      ]));
      expect(raw.userVersion, AppDatabase.expectedSchemaVersion);
      raw.close();

      // Dropping the column frees its pages but leaves the bytes behind, so the
      // migration also VACUUMs. Check the raw file, not just the schema.
      final vacuumed = sqlite3.open(file.path);
      expect(vacuumed.select('PRAGMA freelist_count').first.values.first, 0,
          reason: 'VACUUM ran: no free pages that could hold the old column');
      // Live values that vary run to run must not be mistaken for a leftover
      // PIN: wall-clock timestamps (microseconds like ".791111Z" made this test
      // fail ~1 run in 200), UUIDs, and the random base64 salts/hashes. Remove
      // them first; anything matching after that is a genuine leftover.
      final secrets = [
        for (final r in vacuumed.select('SELECT pin_salt, pin_hash FROM users'))
          for (final v in r.values)
            if (v is String && v.isNotEmpty) v,
      ];
      vacuumed.close();
      final bytes = await file.readAsBytes();
      var haystack = String.fromCharCodes(bytes)
          .replaceAll(
              RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?'), '')
          .replaceAll(
              RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
                  r'[0-9a-f]{12}'),
              '');
      for (final s in secrets) {
        haystack = haystack.replaceAll(s, '');
      }
      for (final pin in const ['1111', '2222']) {
        expect(haystack.contains(pin), isFalse,
            reason: 'the old plaintext PIN $pin is still readable in the file');
      }
    });

    test('the catalog and customers are untouched', () async {
      await buildV10Database();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final snapshot = await LocalCatalogRepository(db).currentSnapshot();
      expect(snapshot.activities, isNotEmpty);
      expect(snapshot.rates, isNotEmpty);
      final customers = await LocalCustomerRepository(db).search('Ravi');
      expect(customers.map((c) => c.name), contains('Ravi'));
    });
  });

  test('migrating twice is a no-op (the app reopens cleanly)', () async {
    final sessionId = await buildV10Database();

    var db = AppDatabase(NativeDatabase(file));
    expect(await LocalSessionRepository(db).getById(sessionId), isNotNull);
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(db.rebuiltFromVersion, 0);
    expect(await LocalSessionRepository(db).getById(sessionId), isNotNull);
    expect(await LocalUserRepository(db).verify('u1', '1111'),
        isA<PinAccepted>());
  });

  /// Builds a genuine v11 database (the current shape minus the v12 additions)
  /// holding one session, segment and payment, stamped user_version 11.
  Future<String> buildV11Database() async {
    final db = AppDatabase(NativeDatabase(file));
    await LocalSeed.apply(db);
    final catalog = LocalCatalogRepository(db);
    final customers = LocalCustomerRepository(db);
    final sessions = LocalSessionRepository(db);
    final snapshot = await catalog.currentSnapshot();
    final who = await customers.create(name: 'Meera');
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: start,
      scheduledEndAt: start.add(const Duration(hours: 1)),
      snapshot: snapshot,
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 2,
    ));
    final sessionId = started.valueOrNull!.id;
    await sessions.recordPayment(RecordPaymentCommand(
      sessionId: sessionId,
      amountPaise: 28000,
      method: PaymentMethod.cash,
    ));
    await db.close();

    // Reverse the v11 -> v12 additions, stamp v11.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS controller_moves');
    raw.execute('DROP TABLE IF EXISTS controller_allocations');
    raw.execute('ALTER TABLE resources DROP COLUMN current_mode');
    raw.execute('PRAGMA user_version = 11');
    raw.close();
    return sessionId;
  }

  group('v11 -> v12 (physical controller allocation)', () {
    test('the v11 fixture is at v11 without the controller_allocations table',
        () async {
      await buildV11Database();
      final raw = sqlite3.open(file.path);
      expect(raw.userVersion, 11);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => '${r['name']}')
          .toSet();
      expect(tables, isNot(contains('controller_allocations')));
      raw.close();
    });

    test('sessions, segments and payments survive, and the new table appears',
        () async {
      final sessionId = await buildV11Database();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final sessions = LocalSessionRepository(db);
      expect(db.rebuiltFromVersion, 0,
          reason: 'this must be a sequential step, not a rebuild');

      final reloaded = await sessions.getById(sessionId);
      expect(reloaded, isNotNull);
      expect(reloaded!.startedAt, start);
      expect((await sessions.paymentsFor(sessionId)).single.amountPaise, 28000);
      expect((await sessions.segmentsFor(sessionId)).single.resourceId, 'hex');

      final check = sqlite3.open(file.path);
      final tables = check
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => '${r['name']}')
          .toSet();
      expect(tables, contains('controller_allocations'));
      final resourceCols = check
          .select("SELECT name FROM pragma_table_info('resources')")
          .map((r) => '${r['name']}')
          .toSet();
      expect(resourceCols, contains('current_mode'));
      final idx = check
          .select("SELECT name FROM sqlite_master WHERE type='index' "
              "AND name='ux_one_open_allocation_per_controller'")
          .map((r) => '${r['name']}')
          .toSet();
      expect(idx, contains('ux_one_open_allocation_per_controller'),
          reason: 'the double-allocation guard survives the migration');
      check.close();
    });

    test('migrating twice is a no-op', () async {
      final sessionId = await buildV11Database();
      var db = AppDatabase(NativeDatabase(file));
      expect(await LocalSessionRepository(db).getById(sessionId), isNotNull);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(db.rebuiltFromVersion, 0);
      expect(await LocalSessionRepository(db).getById(sessionId), isNotNull);
    });
  });

  /// A genuine v12 database: the current shape minus `controller_moves`, with
  /// a live session that holds two TRACKED pads (allocations) and a pad that
  /// an owner moved before the location history existed.
  Future<String> buildV12Database() async {
    final db = AppDatabase(NativeDatabase(file));
    await LocalSeed.apply(db);
    final catalog = LocalCatalogRepository(db);
    final sessions = LocalSessionRepository(db);
    final who = await LocalCustomerRepository(db).create(name: 'Anu');
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: start,
      scheduledEndAt: start.add(const Duration(hours: 1)),
      snapshot: await catalog.currentSnapshot(),
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 2,
      controllerIds: ['ctl_hex_1', 'ctl_hex_2'],
    ));
    await sessions.recordPayment(RecordPaymentCommand(
      sessionId: started.valueOrNull!.id,
      amountPaise: 28000,
      method: PaymentMethod.upi,
    ));
    // A pad relocated under v12: only its location columns record it.
    await (db.update(db.controllers)..where((t) => t.id.equals('ctl_void_1')))
        .write(const ControllersCompanion(
      currentResourceId: Value('ghost'),
      loanReturnTo: Value('void'),
    ));
    await db.close();
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS controller_moves');
    raw.execute('PRAGMA user_version = 12');
    raw.close();
    return started.valueOrNull!.id;
  }

  group('v12 -> v13 (controller location history)', () {
    test('live sessions, their tracked pads and pad locations survive; the '
        'history table appears empty and works', () async {
      final sessionId = await buildV12Database();
      final before = sqlite3.open(file.path);
      expect(before.userVersion, 12);
      expect(
          before
              .select(
                  "SELECT name FROM sqlite_master WHERE name='controller_moves'")
              .isEmpty,
          isTrue);
      before.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(db.rebuiltFromVersion, 0, reason: 'sequential, not a rebuild');
      final s = await LocalSessionRepository(db).getById(sessionId);
      expect(s, isNotNull);
      expect(s!.isActive, isTrue);
      final sessions = LocalSessionRepository(db);
      expect((await sessions.segmentsFor(sessionId)).single.controllerCount, 2);
      expect((await sessions.paymentsFor(sessionId)).single.amountPaise, 28000);
      final alloc = LocalControllerAllocationRepository(db);
      expect({for (final a in await alloc.openPadAllocations()) a.controllerId},
          {'ctl_hex_1', 'ctl_hex_2'},
          reason: 'pads held by a running session stay held');
      final void1 = (await LocalCatalogRepository(db).controllers())
          .firstWhere((c) => c.id == 'ctl_void_1');
      expect(void1.currentResourceId, 'ghost');
      expect(void1.loanReturnTo, 'void');
      expect(await alloc.movesForController('ctl_void_1'), isEmpty);

      // The new history records from now on.
      await alloc.moveController(
          controllerId: 'ctl_void_1',
          toResourceId: 'void',
          kind: ControllerMoveKind.returnHome);
      final moves = await alloc.movesForController('ctl_void_1');
      expect(moves.single.fromResourceId, 'ghost');
      expect(moves.single.toResourceId, 'void');

      final check = sqlite3.open(file.path);
      expect(check.userVersion, AppDatabase.expectedSchemaVersion);
      expect(
          check
              .select("SELECT name FROM sqlite_master WHERE type='index' "
                  "AND name='ix_moves_controller'")
              .isNotEmpty,
          isTrue);
      check.close();
    });
  });
}
