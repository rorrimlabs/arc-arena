/// Start-up with a stored sign-in. Regression for "permission denied for
/// function my_arenas (42501)" after "Invalid Refresh Token: Refresh Token Not
/// Found": the refused refresh dropped the session, and the arena list was then
/// requested with only the publishable key — as `anon`, which (correctly) may
/// call nothing. Drives the real Supabase client against a fake server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arena_ops/app/sync/secure_session_storage.dart';
import 'package:arena_ops/app/sync/stored_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'sb_publishable_test';
const _userId = '00000000-0000-4000-8000-000000000001';

String _jwt(DateTime exp) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _userId, 'role': 'authenticated', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}'
      '.sig';
}

Map<String, Object> _session(String accessToken, String refreshToken) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': refreshToken,
  'user': {
    'id': _userId,
    'aud': 'authenticated',
    'email': 'staff@arena.example',
    'created_at': '2026-10-01T00:00:00Z',
    'app_metadata': <String, Object>{},
    'user_metadata': <String, Object>{},
  },
};

/// A fake backend: answers the refresh with [refresh], records how
/// `my_arenas` was authorised.
class _Backend {
  _Backend(this.refresh);
  final Future<http.Response> Function() refresh;
  int refreshCalls = 0;
  final rpcAuth = <String?>[];

  late final client = SupabaseClient(
    'http://backend.test',
    _key,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      if (req.url.path == '/auth/v1/token') {
        refreshCalls++;
        return refresh();
      }
      if (req.url.path == '/rest/v1/rpc/my_arenas') {
        rpcAuth.add(req.headers['Authorization']);
        return http.Response(
          '[]',
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    }),
  );

  /// What supabase_flutter does at start-up: restore the saved session as is.
  Future<void> restore({required DateTime accessExpiry}) =>
      client.auth.setInitialSession(
        jsonEncode(_session(_jwt(accessExpiry), 'stored-refresh-token')),
      );
}

http.Response _json(int status, Map<String, Object> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  final past = DateTime.now().subtract(const Duration(hours: 2));
  final future = DateTime.now().add(const Duration(hours: 1));

  test('nothing stored: sign in, without calling the server', () async {
    final b = _Backend(() async => fail('no refresh expected'));
    expect(await checkStoredSession(b.client.auth), StoredSession.signInNeeded);
    expect(b.refreshCalls, 0);
    await b.client.dispose();
  });

  test('refresh_token_not_found: sign in again, never call as anon', () async {
    final b = _Backend(
      () async => _json(400, {
        'code': 400,
        'error_code': 'refresh_token_not_found',
        'msg': 'Invalid Refresh Token: Refresh Token Not Found',
      }),
    );
    await b.restore(accessExpiry: past);
    expect(
      b.client.auth.currentSession,
      isNotNull,
      reason: 'restored as is, so the app used to call my_arenas at once',
    );

    expect(await checkStoredSession(b.client.auth), StoredSession.signInNeeded);
    expect(
      b.client.auth.currentSession,
      isNull,
      reason: 'the server refused it',
    );

    // The root cause: past this point a call carries only the publishable key
    // (role anon → 42501). The check above is what keeps the app from it.
    await b.client.rpc<dynamic>('my_arenas');
    expect(b.rpcAuth.single, 'Bearer $_key');
    await b.client.dispose();
  });

  // gotrue retries a refresh that cannot reach the server (or gets a 5xx) for
  // about 10 s before giving up, hence the timeout.
  test('no connection: the sign-in is kept for an offline start', () async {
    final b = _Backend(
      () async => throw const SocketException('Network is unreachable'),
    );
    await b.restore(accessExpiry: past);
    expect(await checkStoredSession(b.client.auth), StoredSession.offline);
    expect(b.client.auth.currentSession, isNotNull);
    await b.client.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('Auth never answers (captive or very weak network): the sign-in is '
      'kept and the start goes offline instead of spinning', () async {
    final hang = Completer<http.Response>();
    final b = _Backend(() => hang.future);
    await b.restore(accessExpiry: past);
    expect(
      await checkStoredSession(
        b.client.auth,
        timeout: const Duration(milliseconds: 200),
      ),
      StoredSession.offline,
    );
    expect(b.client.auth.currentSession, isNotNull);
    // The refresh lands late (in the app it carries on in the background).
    hang.complete(_json(200, _session(_jwt(future), 'rotated-refresh-token')));
    await b.client.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
    'expired but refreshable: refreshed once, then called as the user',
    () async {
      final fresh = _jwt(future);
      final b = _Backend(
        () async => _json(200, _session(fresh, 'rotated-refresh-token')),
      );
      await b.restore(accessExpiry: past);
      expect(await checkStoredSession(b.client.auth), StoredSession.valid);
      await b.client.rpc<dynamic>('my_arenas');
      expect(b.rpcAuth.single, 'Bearer $fresh');
      expect(b.refreshCalls, 1);
      await b.client.dispose();
    },
  );

  test('still-valid session: used as is, no refresh', () async {
    final b = _Backend(() async => fail('no refresh expected'));
    await b.restore(accessExpiry: future);
    expect(await checkStoredSession(b.client.auth), StoredSession.valid);
    expect(b.refreshCalls, 0);
    await b.client.dispose();
  });

  test('stored sign-ins are kept per backend', () {
    final local = SecureSessionStorage.keyFor('http://127.0.0.1:54431');
    final hosted = SecureSessionStorage.keyFor(
      'https://ouxvtvlzhxddmqirmnxo.supabase.co',
    );
    expect(local, isNot(hosted));
    expect(local, 'arena_ops.supabase.session@127.0.0.1:54431');
    expect(
      SecureSessionStorage.keyFor('http://127.0.0.1:54321'),
      isNot(local),
      reason: 'two local stacks on different ports are different backends',
    );
  });

  group('start-up failures (audit H2: offline must never sign staff out)', () {
    test('offline while the expired token needed refreshing: OFFLINE, the '
        'stored sign-in is kept', () async {
      final b = _Backend(
        () async => throw const SocketException('Network is unreachable'),
      );
      await b.restore(accessExpiry: past);
      Object? error;
      try {
        await b.client.rpc<dynamic>('my_arenas');
      } on Object catch (e) {
        error = e;
      }
      expect(
        error,
        isA<AuthRetryableFetchException>(),
        reason: 'what the real client throws: an AuthException subclass',
      );
      expect(
        classifyStartupFailure(
          error!,
          hasSession: b.client.auth.currentSession != null,
        ),
        StartupFailure.offline,
      );
      expect(
        b.client.auth.currentSession,
        isNotNull,
        reason: 'nothing deleted',
      );
      expect(b.rpcAuth, isEmpty, reason: 'and nothing was sent as anon');
      await b.client.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test(
      'refresh token rejected: SIGN IN AGAIN (the session is gone)',
      () async {
        final b = _Backend(
          () async => _json(400, {
            'code': 400,
            'error_code': 'refresh_token_not_found',
            'msg': 'Invalid Refresh Token: Refresh Token Not Found',
          }),
        );
        await b.restore(accessExpiry: past);
        Object? error;
        try {
          await b.client.rpc<dynamic>('my_arenas');
        } on Object catch (e) {
          error = e;
        }
        expect(error, isA<AuthException>());
        expect(
          classifyStartupFailure(
            error!,
            hasSession: b.client.auth.currentSession != null,
          ),
          StartupFailure.signInNeeded,
        );
        await b.client.dispose();
      },
    );

    test('the classification table', () {
      PostgrestException pg(String code) =>
          PostgrestException(message: 'x', code: code);
      final cases = <(Object, bool, StartupFailure)>[
        (const SocketException('down'), true, StartupFailure.offline),
        (TimeoutException('slow'), true, StartupFailure.offline),
        (
          AuthRetryableFetchException(message: 'no network'),
          true,
          StartupFailure.offline,
        ),
        (pg('503'), true, StartupFailure.offline),
        (
          AuthApiException(
            'Invalid Refresh Token',
            statusCode: '400',
            code: 'refresh_token_not_found',
          ),
          true,
          StartupFailure.signInNeeded,
        ),
        (pg('PGRST301'), true, StartupFailure.signInNeeded),
        (pg('PGRST303'), true, StartupFailure.signInNeeded),
        (pg('42501'), true, StartupFailure.serverRefused),
        (pg('42501'), false, StartupFailure.signInNeeded),
        (const SocketException('down'), false, StartupFailure.signInNeeded),
        (StateError('weird'), true, StartupFailure.offline),
      ];
      for (final (error, hasSession, expected) in cases) {
        expect(
          classifyStartupFailure(error, hasSession: hasSession),
          expected,
          reason: '$error (session: $hasSession)',
        );
      }
    });
  });
}
