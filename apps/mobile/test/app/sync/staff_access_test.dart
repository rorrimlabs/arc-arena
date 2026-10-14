/// The staff app's sign-in decisions without a server: reading my_arenas,
/// deciding access from the device's staff list (and re-checking once when
/// the server just confirmed access the device does not show yet), the words
/// a person sees for each failure, and a keystore that cannot be read.
library;

import 'dart:io';

import 'package:arena_ops/app/sync/secure_session_storage.dart';
import 'package:arena_ops/app/sync/staff_access.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('my_arenas rows', () {
    test('reads each membership; inactive ones are kept and flagged', () {
      final m = parseMemberships([
        {
          'arena_id': 'a1',
          'arena_name': '404 Arena',
          'name': 'Asha',
          'role': 'staff',
          'perms': ['start'],
          'active': true,
        },
        {'arena_id': 'a2', 'arena_name': 'Old', 'name': 'Asha', 'active': false},
      ]);
      expect(m, [
        (arenaId: 'a1', arenaName: '404 Arena', name: 'Asha', active: true),
        (arenaId: 'a2', arenaName: 'Old', name: 'Asha', active: false),
      ]);
    });

    test('a row it cannot read never fails the list, and access is never '
        'assumed', () {
      final m = parseMemberships([
        {'arena_name': 'no id'},
        {'arena_id': 'a3', 'arena_name': null, 'name': null},
        'garbage',
      ]);
      expect(m, [(arenaId: 'a3', arenaName: 'Arena', name: '', active: false)]);
      expect(parseMemberships(null), isEmpty);
      expect(parseMemberships({'arena_id': 'x'}), isEmpty);
    });
  });

  group('which arena opens by itself (staying signed in across restarts)', () {
    Membership m(String id, {bool active = true}) =>
        (arenaId: id, arenaName: id, name: 'Asha', active: active);

    test('the only active arena opens, whatever was last', () {
      expect(arenaToOpen([m('a'), m('b', active: false)], null), m('a'));
      expect(arenaToOpen([m('a'), m('b', active: false)], 'b'), m('a'));
    });

    test('with several, the one last worked in here reopens', () {
      expect(arenaToOpen([m('a'), m('b')], 'b'), m('b'));
    });

    test('the list is shown when there is no usable last arena', () {
      expect(arenaToOpen([m('a'), m('b')], null), isNull);
      expect(arenaToOpen([m('a'), m('b')], 'gone'), isNull);
      expect(
        arenaToOpen([m('a'), m('b'), m('c', active: false)], 'c'),
        isNull,
        reason: 'access to the last one was turned off',
      );
      expect(arenaToOpen([m('a', active: false)], 'a'), isNull);
      expect(arenaToOpen(const [], 'a'), isNull);
    });
  });

  group('access from the device staff list', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> member(String id, {bool active = true, List<String>? perms}) =>
        db.into(db.users).insertOnConflictUpdate(
              UsersCompanion.insert(
                id: id,
                name: 'Asha',
                perms: perms ?? ['start', 'bill'],
                active: Value(active),
              ),
            );

    test('an active member gets their server permissions — staff, not owner',
        () async {
      await member('u1');
      final access = await localAccess(db, 'u1');
      expect(access, isA<AccessGranted>());
      final user = (access as AccessGranted).user;
      expect(user.perms, {Permission.start, Permission.bill});
      expect(user.isOwner, isFalse);
    });

    test('turned off, or never downloaded, is not access', () async {
      await member('u1', active: false);
      expect(await localAccess(db, 'u1'), isA<AccessTurnedOff>());
      expect(await localAccess(db, 'nobody'), isA<AccessNotOnDevice>());
    });

    test('the server says active but the device copy is older: sync once, '
        'then open — never "turned off" for a valid member', () async {
      await member('u1', active: false);
      var syncs = 0;
      final access = await confirmAccess(
        db: db,
        userId: 'u1',
        confirmedOnline: true,
        sync: () async {
          syncs++;
          await member('u1'); // the pull brings the current profile
        },
      );
      expect(syncs, 1);
      expect(access, isA<AccessGranted>());
    });

    test('a profile that arrives with that sync opens too', () async {
      final access = await confirmAccess(
        db: db,
        userId: 'u2',
        confirmedOnline: true,
        sync: () => member('u2'),
      );
      expect(access, isA<AccessGranted>());
    });

    test('still off on the server after the sync: stays off', () async {
      await member('u1', active: false);
      final access = await confirmAccess(
        db: db,
        userId: 'u1',
        confirmedOnline: true,
        sync: () async {},
      );
      expect(access, isA<AccessTurnedOff>());
    });

    test('offline start: the device copy decides, no sync attempted', () async {
      await member('u1', active: false);
      var syncs = 0;
      final access = await confirmAccess(
        db: db,
        userId: 'u1',
        confirmedOnline: false,
        sync: () async => syncs++,
      );
      expect(access, isA<AccessTurnedOff>());
      expect(syncs, 0);
    });

    test('already granted: opens without an extra sync', () async {
      await member('u1');
      var syncs = 0;
      await confirmAccess(
        db: db,
        userId: 'u1',
        confirmedOnline: true,
        sync: () async => syncs++,
      );
      expect(syncs, 0);
    });
  });

  group('what the person is told', () {
    test('wrong password: says so, and how an invited person gets a password',
        () {
      final m = signInFailureMessage(
        const AuthException('Invalid login credentials',
            statusCode: '400', code: 'invalid_credentials'),
      );
      expect(m, contains("don't match a login"));
      expect(m, contains('invitation e-mail'));
      // Older Auth servers send no code, only the text.
      expect(
        signInFailureMessage(const AuthException('Invalid login credentials')),
        m,
      );
    });

    test('unconfirmed e-mail, rate limit, blocked login', () {
      expect(
        signInFailureMessage(
          const AuthException('Email not confirmed', code: 'email_not_confirmed'),
        ),
        contains('not confirmed yet'),
      );
      expect(
        signInFailureMessage(
          const AuthException('rate', statusCode: '429', code: 'x'),
        ),
        contains('Too many attempts'),
      );
      expect(
        signInFailureMessage(const AuthException('b', code: 'user_banned')),
        contains('blocked'),
      );
    });

    test('no network or a server error reads as unreachable, not a wrong '
        'password', () {
      for (final e in <Object>[
        AuthRetryableFetchException(),
        const SocketException('Connection refused'),
        const AuthException('bad gateway', statusCode: '502'),
      ]) {
        expect(signInFailureMessage(e), offlineMessage);
      }
    });

    test('never shows the server\'s own text', () {
      final m = signInFailureMessage(
        const AuthException('internal: relation auth.x does not exist',
            code: 'unexpected_failure'),
      );
      expect(m, isNot(contains('relation')));
      expect(m, contains('unexpected_failure'));
    });

    test('the arena list: a server without the staff app update, a refusal',
        () {
      expect(
        arenaListFailureMessage(
          const PostgrestException(message: 'Could not find', code: 'PGRST202'),
        ),
        contains("isn't set up for the staff app"),
      );
      expect(
        arenaListFailureMessage(
          const PostgrestException(message: 'permission denied', code: '42501'),
        ),
        contains('refused to list your arenas'),
      );
      expect(
        arenaListFailureMessage(
          const PostgrestException(message: 'syntax error at …', code: '42601'),
        ),
        "Couldn't load your arenas (42601). Try again.",
      );
    });

    test('the first download', () {
      expect(
        firstDownloadFailureMessage(
          const SyncStatus(state: SyncState.authProblem, accessRevoked: true),
          '404 Arena',
        ),
        'Your access to 404 Arena is turned off. Ask the owner.',
      );
      expect(
        firstDownloadFailureMessage(
          const SyncStatus(state: SyncState.offline),
          '404 Arena',
        ),
        contains('must download once'),
      );
      expect(
        firstDownloadFailureMessage(
          const SyncStatus(
            state: SyncState.error,
            message: 'Sync failed: type Null is not a subtype',
          ),
          '404 Arena',
        ),
        isNot(contains('subtype')),
      );
    });
  });

  group('stored sign-in', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('a keystore that cannot be read means "sign in again", not a crash at '
        'start', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'read') {
          throw PlatformException(code: 'Exception', message: 'BadPaddingException');
        }
        return null;
      });
      final storage = SecureSessionStorage(backendUrl: 'http://127.0.0.1:54431');
      await storage.initialize();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
      // Only the legacy shared key is deleted (initialize); the session entry
      // is kept — a read error can pass (a locked iPhone refuses reads).
      expect(calls.where((c) => c == 'delete'), hasLength(1));
    });

    test('a keystore that refuses a write does not fail the sign-in', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'Exception', message: 'KeyStoreException');
      });
      final storage = SecureSessionStorage(backendUrl: 'http://127.0.0.1:54431');
      await expectLater(storage.persistSession('{}'), completes);
      await expectLater(storage.removePersistedSession(), completes);
    });
  });
}
