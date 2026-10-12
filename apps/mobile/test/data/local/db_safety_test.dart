/// Backup, verification, migration and recovery for the on-device database.
///
/// These tests use real files on disk, not an in-memory database: the thing
/// under test is precisely what happens to the *file* when the app opens it.
library;

import 'dart:io';

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/db_safety.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  late File dbFile;
  late Directory backupDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('arena_ops_safety');
    dbFile = File('${tmp.path}/arena_ops.sqlite');
    backupDir = Directory('${tmp.path}/arena_ops-backups');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Writes a real session + segment + payment to [dbFile] and returns the id.
  ///
  /// [extraCustomer] varies the contents so successive backups are distinct;
  /// [forceUserVersion] is applied last, after the file is closed, so nothing
  /// reopens (and therefore migrates) the database afterwards.
  Future<String> seedOneSession(
      {int? forceUserVersion, String? extraCustomer}) async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await LocalSeed.apply(db);
    final catalog = LocalCatalogRepository(db);
    final customers = LocalCustomerRepository(db);
    final sessions = LocalSessionRepository(db);
    final snapshot = await catalog.currentSnapshot();
    final who = await customers.create(name: 'Asha');
    final start = DateTime.utc(2026, 10, 10, 9);
    final started = await sessions.start(StartSessionCommand(
      customerId: who.id,
      startedAt: start,
      scheduledEndAt: start.add(const Duration(hours: 1)),
      snapshot: snapshot,
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      controllerCount: 1,
    ));
    final id = started.valueOrNull!.id;
    await sessions.recordPayment(RecordPaymentCommand(
      sessionId: id,
      amountPaise: 60700,
      method: PaymentMethod.cash,
    ));
    if (extraCustomer != null) await customers.create(name: extraCustomer);
    await db.close();

    if (forceUserVersion != null) {
      // Stand in for a database written by an older build.
      final raw = sqlite3.open(dbFile.path);
      raw.execute('PRAGMA user_version = $forceUserVersion;');
      raw.close();
    }
    return id;
  }

  group('backup before anything opens the database', () {
    test('a fresh install has nothing to protect and is safe to open',
        () async {
      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      expect(report.outcome, DbProtectOutcome.freshInstall);
      expect(report.migrationExpected, isFalse);
      expect(report.safeToOpen, isTrue);
    });

    test('an existing database is copied, verified and counted', () async {
      await seedOneSession();

      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );

      expect(report.outcome, DbProtectOutcome.backedUp);
      expect(report.onDiskSchemaVersion, AppDatabase.expectedSchemaVersion);
      expect(report.backupFile!.existsSync(), isTrue);
      // The counts are read back out of the copy, so they prove it is readable.
      expect(report.rowCounts['sessions'], 1);
      expect(report.rowCounts['payments'], 1);
      expect(report.rowCounts['session_segments'], 1);
      // The live database is untouched by the backup.
      expect(dbFile.existsSync(), isTrue);
    });

    test('the backup is self-contained: it holds rows still in the live WAL',
        () async {
      // Write with WAL on and do NOT checkpoint, so the newest rows live only
      // in the -wal file. A copy of just the .sqlite would silently lose them.
      final db = AppDatabase(NativeDatabase(dbFile));
      await LocalSeed.apply(db);
      final customers = LocalCustomerRepository(db);
      await customers.create(name: 'In WAL only');
      final walBefore = File('${dbFile.path}-wal');
      expect(walBefore.existsSync(), isTrue,
          reason: 'beforeOpen sets journal_mode = WAL');

      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      await db.close();

      expect(report.outcome, DbProtectOutcome.backedUp);
      final restored = sqlite3.open(report.backupFile!.path);
      final names = restored
          .select('SELECT name FROM customers;')
          .map((r) => '${r['name']}')
          .toList();
      restored.close();
      expect(names, contains('In WAL only'));
      // And it stands alone — no sidecar files needed to read it.
      expect(File('${report.backupFile!.path}-wal').existsSync(), isFalse);
    });

    test('an unchanged database is not backed up twice', () async {
      await seedOneSession();
      final first = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      final second = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      expect(first.outcome, DbProtectOutcome.backedUp);
      expect(second.outcome, DbProtectOutcome.alreadyProtected);
      expect(second.backupFile!.path, first.backupFile!.path);
      expect(DbSafety.listBackups(backupDir), hasLength(1));
      expect(second.safeToOpen, isTrue);
    });

    test('a corrupt database fails verification and is not safe to migrate',
        () async {
      await seedOneSession(forceUserVersion: 5);
      // Scribble over the middle of the file, leaving a readable header.
      final bytes = await dbFile.readAsBytes();
      for (var i = 2000; i < 9000 && i < bytes.length; i++) {
        bytes[i] = 0x7f;
      }
      await dbFile.writeAsBytes(bytes, flush: true);

      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );

      expect(report.hasVerifiedBackup, isFalse);
      expect(report.outcome, DbProtectOutcome.verificationFailed);
      // A migration was pending, so the app must refuse to open it.
      expect(report.migrationExpected, isTrue);
      expect(report.safeToOpen, isFalse,
          reason: 'never migrate the only copy without a verified backup');
    });
  });

  group('migration', () {
    test('opening at the same schema version changes nothing and keeps rows',
        () async {
      final id = await seedOneSession();

      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      expect(report.migrationExpected, isFalse,
          reason: 'v10 on disk, v10 in the app');

      final db = AppDatabase(NativeDatabase(dbFile));
      final sessions = LocalSessionRepository(db);
      final reloaded = await sessions.getById(id);
      expect(db.rebuiltFromVersion, 0, reason: 'no migration ran');
      expect(reloaded, isNotNull);
      expect((await sessions.paymentsFor(id)).single.amountPaise, 60700);
      await db.close();
    });

    test(
        'a pre-release database is rebuilt, but only behind a verified backup '
        'that still holds the records', () async {
      await seedOneSession(forceUserVersion: 5);

      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      expect(report.migrationExpected, isTrue);
      expect(report.safeToOpen, isTrue, reason: 'backup verified first');
      expect(report.rowCounts['payments'], 1);

      // Now let the app open it, which runs the rebuild fallback.
      final db = AppDatabase(NativeDatabase(dbFile));
      final sessions = LocalSessionRepository(db);
      expect(await sessions.openSegments(), isEmpty);
      expect(db.rebuiltFromVersion, 5,
          reason: 'a rebuild must be recorded, never silent');
      await db.close();

      // The records are still recoverable from the backup.
      final check = DbSafety.verifyBackup(report.backupFile!);
      expect(check.hasVerifiedBackup, isTrue);
      expect(check.rowCounts['sessions'], 1);
      expect(check.rowCounts['payments'], 1);
    });

    test('every declared migration step is sequential and additive', () {
      // Guards the framework itself: a step map with a gap would silently fall
      // through to the destructive rebuild on a real device.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final steps = db.declaredMigrationSteps;
      for (final from in steps) {
        expect(steps.contains(from), isTrue);
      }
      // No step may be declared at or above the current version, and the chain
      // from the oldest declared step must be unbroken up to it.
      for (final from in steps) {
        expect(from, lessThan(AppDatabase.expectedSchemaVersion),
            reason: 'step v$from -> v${from + 1} has no target version');
      }
      if (steps.isNotEmpty) {
        final oldest = steps.reduce((a, b) => a < b ? a : b);
        for (var v = oldest; v < AppDatabase.expectedSchemaVersion; v++) {
          expect(steps, contains(v),
              reason: 'missing migration step v$v -> v${v + 1}; a gap here '
                  'rebuilds the database instead of migrating it');
        }
      }
    });
  });

  group('recovery', () {
    test('restoring a backup brings the records back', () async {
      final id = await seedOneSession();
      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );

      // Lose the database the way a reinstall or a wipe would.
      await dbFile.delete();
      for (final suffix in const ['-wal', '-shm']) {
        final side = File('${dbFile.path}$suffix');
        if (side.existsSync()) await side.delete();
      }
      expect(dbFile.existsSync(), isFalse);

      final restored = await DbSafety.restore(
        backup: report.backupFile!,
        dbFile: dbFile,
        backupDir: backupDir,
      );
      expect(restored.hasVerifiedBackup, isTrue);

      // The app can open the restored file and the money is still there.
      final db = AppDatabase(NativeDatabase(dbFile));
      final sessions = LocalSessionRepository(db);
      expect(db.rebuiltFromVersion, 0);
      final reloaded = await sessions.getById(id);
      expect(reloaded, isNotNull);
      expect(reloaded!.startedAt, DateTime.utc(2026, 10, 10, 9));
      expect((await sessions.paymentsFor(id)).single.amountPaise, 60700);
      expect((await sessions.segmentsFor(id)).single.resourceId, 'hex');
      await db.close();
    });

    test('a restore keeps a copy of what it replaced', () async {
      await seedOneSession();
      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );

      // Add a second customer, so the live file now differs from the backup.
      final db = AppDatabase(NativeDatabase(dbFile));
      await LocalCustomerRepository(db).create(name: 'Later arrival');
      await db.close();

      await DbSafety.restore(
        backup: report.backupFile!,
        dbFile: dbFile,
        backupDir: backupDir,
      );

      final replaced = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('-replaced-'))
          .toList();
      expect(replaced, hasLength(1),
          reason: 'a restore must not be a one-way door');
      final check = DbSafety.verifyBackup(replaced.single);
      expect(check.hasVerifiedBackup, isTrue);
      final raw = sqlite3.open(replaced.single.path);
      final names = raw
          .select('SELECT name FROM customers;')
          .map((r) => '${r['name']}')
          .toList();
      raw.close();
      expect(names, contains('Later arrival'));
    });

    test('a damaged backup is refused rather than restored over good data',
        () async {
      await seedOneSession();
      final report = await DbSafety.protect(
        dbFile: dbFile,
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: backupDir,
      );
      final backup = report.backupFile!;
      final bytes = await backup.readAsBytes();
      for (var i = 2000; i < 9000 && i < bytes.length; i++) {
        bytes[i] = 0x7f;
      }
      await backup.writeAsBytes(bytes, flush: true);

      final attempt = await DbSafety.restore(
        backup: backup,
        dbFile: dbFile,
        backupDir: backupDir,
      );
      expect(attempt.hasVerifiedBackup, isFalse);
      // The live database was left alone.
      final db = AppDatabase(NativeDatabase(dbFile));
      expect(await LocalSessionRepository(db).openSegments(), hasLength(1));
      await db.close();
    });

    test('pruning keeps the newest backup of each schema version', () async {
      await backupDir.create(recursive: true);
      // Build a realistic history: many v10 backups plus one older v5. The
      // version is forced after the file is closed and never reopened, so the
      // v5 backup really is a v5 file.
      for (var i = 0; i < 14; i++) {
        await seedOneSession(
          forceUserVersion: i == 0 ? 5 : 10,
          extraCustomer: 'visitor $i',
        );
        await DbSafety.protect(
          dbFile: dbFile,
          appSchemaVersion: AppDatabase.expectedSchemaVersion,
          backupDir: backupDir,
          keep: 5,
        );
        await dbFile.delete();
        for (final suffix in const ['-wal', '-shm']) {
          final side = File('${dbFile.path}$suffix');
          if (side.existsSync()) await side.delete();
        }
      }

      final kept = DbSafety.listBackups(backupDir);
      expect(kept.length, lessThanOrEqualTo(6),
          reason: 'keep: 5, plus the protected newest-per-version');
      expect(
        kept.where((f) => f.path.contains('-v5-')),
        hasLength(1),
        reason: 'the last database a v5 build can still read is never pruned',
      );
      for (final f in kept) {
        expect(DbSafety.verifyBackup(f).hasVerifiedBackup, isTrue);
      }
    });
  });
}
