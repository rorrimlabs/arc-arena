/// PIN storage and failed-attempt protection.
library;

import 'dart:io';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/pin_credential.dart';
import 'package:arena_ops/domain/repositories/user_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late LocalUserRepository users;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    clock = FakeClock(DateTime.utc(2026, 10, 10, 9));
    users = LocalUserRepository(db, clock);
  });

  tearDown(() async => db.close());

  group('PIN storage', () {
    test('no PIN is recoverable from the database', () async {
      final rows = await db.select(db.users).get();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.pinHash, isNotNull);
        expect(r.pinSalt, isNotNull);
        expect(r.pinIterations, PinCredential.defaultIterations);
        // The seeded PINs must not appear anywhere in the stored credential.
        expect(r.pinHash, isNot(contains('1111')));
        expect(r.pinHash, isNot(contains('2222')));
      }
      // And the table itself no longer has a column that could hold one.
      final columns = await db
          .customSelect("SELECT name FROM pragma_table_info('users')")
          .get();
      expect(
        columns.map((r) => r.read<String>('name')),
        isNot(contains('pin')),
      );
    });

    test('two accounts with the same PIN get different hashes', () async {
      await users.upsert(
        const AppUser(id: 'a', name: 'A', perms: {Permission.start}),
        newPin: '4321',
      );
      await users.upsert(
        const AppUser(id: 'b', name: 'B', perms: {Permission.start}),
        newPin: '4321',
      );
      final a = await (db.select(db.users)..where((t) => t.id.equals('a')))
          .getSingle();
      final b = await (db.select(db.users)..where((t) => t.id.equals('b')))
          .getSingle();
      expect(a.pinSalt, isNot(b.pinSalt));
      expect(a.pinHash, isNot(b.pinHash),
          reason: 'a shared hash would let one staff member use the other PIN');
    });

    test('the right PIN is accepted and a wrong one is not', () async {
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
      expect(await users.verify('u1', '1112'), isA<PinRejected>());
    });

    test('editing an account without a new PIN keeps the old PIN working',
        () async {
      final owner = (await users.getById('u1'))!;
      await users.upsert(owner.copyWith(name: 'Arjun M.'));
      expect((await users.getById('u1'))!.name, 'Arjun M.');
      expect(await users.verify('u1', '1111'), isA<PinAccepted>(),
          reason: 'a rename must not silently reset the PIN');
    });

    test('setting a new PIN replaces the old one', () async {
      final owner = (await users.getById('u1'))!;
      await users.upsert(owner, newPin: '9876');
      expect(await users.verify('u1', '1111'), isA<PinRejected>());
      expect(await users.verify('u1', '9876'), isA<PinAccepted>());
    });

    test('an account with no PIN cannot sign in', () async {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'nopin',
            name: 'No PIN',
            perms: const ['start'],
          ));
      expect(await users.verify('nopin', '0000'), isA<PinUnavailable>());
      expect(await users.hasPin('nopin'), isFalse);
      expect(await users.hasPin('u1'), isTrue);
    });

    test('a deactivated account cannot sign in with a valid PIN', () async {
      final owner = (await users.getById('u1'))!;
      await users.upsert(owner.copyWith(active: false));
      expect(await users.verify('u1', '1111'), isA<PinUnavailable>());
    });
  });

  group('failed-attempt protection', () {
    test('locks the account after five wrong PINs', () async {
      for (var i = 1; i <= 4; i++) {
        final attempt = await users.verify('u1', '0000');
        expect(attempt, isA<PinRejected>(), reason: 'attempt $i');
        expect((attempt as PinRejected).attemptsLeft, 5 - i);
      }
      final fifth = await users.verify('u1', '0000');
      expect(fifth, isA<PinLockedOut>());
      expect((fifth as PinLockedOut).retryIn,
          LocalUserRepository.lockoutLadder.first);
    });

    test('while locked, even the correct PIN is refused', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      expect(await users.verify('u1', '1111'), isA<PinLockedOut>(),
          reason: 'a lockout that the right PIN can open is not a lockout');
    });

    test('the lockout lifts once the wait has passed', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      clock.advance(LocalUserRepository.lockoutLadder.first -
          const Duration(seconds: 1));
      expect(await users.verify('u1', '1111'), isA<PinLockedOut>());

      clock.advance(const Duration(seconds: 2));
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
    });

    test('each further wrong PIN after a lockout waits longer', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      var previous = LocalUserRepository.lockoutLadder.first;
      for (final expected in LocalUserRepository.lockoutLadder.skip(1)) {
        clock.advance(previous + const Duration(seconds: 1));
        final attempt = await users.verify('u1', '0000');
        expect(attempt, isA<PinLockedOut>());
        expect((attempt as PinLockedOut).retryIn, expected,
            reason: 'the ladder must escalate, not reset');
        previous = expected;
      }
      // And it caps rather than growing without bound.
      clock.advance(previous + const Duration(seconds: 1));
      final capped = await users.verify('u1', '0000');
      expect((capped as PinLockedOut).retryIn,
          LocalUserRepository.lockoutLadder.last);
    });

    test('a correct PIN clears the failure count', () async {
      await users.verify('u1', '0000');
      await users.verify('u1', '0000');
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
      // Back to a full set of attempts.
      final attempt = await users.verify('u1', '0000');
      expect((attempt as PinRejected).attemptsLeft, 4);
    });

    test('the lockout survives restarting the app', () async {
      // Persisted, not in-memory: force-quitting must not hand back a fresh
      // five attempts. Uses a file so the data really leaves the process.
      final dir = await Directory.systemTemp.createTemp('arena_ops_lockout');
      final file = File('${dir.path}/arena.sqlite');
      addTearDown(() async => dir.delete(recursive: true));

      var disk = AppDatabase(NativeDatabase(file));
      await LocalSeed.apply(disk);
      var repo = LocalUserRepository(disk, clock);
      for (var i = 0; i < 5; i++) {
        await repo.verify('u1', '0000');
      }
      expect(await repo.verify('u1', '1111'), isA<PinLockedOut>());
      await disk.close();

      disk = AppDatabase(NativeDatabase(file));
      repo = LocalUserRepository(disk, clock);
      expect(await repo.verify('u1', '1111'), isA<PinLockedOut>(),
          reason: 'a restart must not clear the lockout');
      await disk.close();
    });

    test('an owner can clear a lockout from Settings', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      expect(await users.verify('u1', '1111'), isA<PinLockedOut>());
      await users.clearLockout('u1');
      expect(await users.verify('u1', '1111'), isA<PinAccepted>());
    });

    test('a new PIN clears a lockout', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      final owner = (await users.getById('u1'))!;
      await users.upsert(owner, newPin: '5555');
      expect(await users.verify('u1', '5555'), isA<PinAccepted>());
    });

    test('one account locking does not lock another', () async {
      for (var i = 0; i < 5; i++) {
        await users.verify('u1', '0000');
      }
      expect(await users.verify('u1', '1111'), isA<PinLockedOut>());
      expect(await users.verify('u2', '2222'), isA<PinAccepted>(),
          reason: 'the other person on shift must still be able to work');
    });
  });
}
