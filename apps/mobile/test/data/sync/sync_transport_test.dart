/// SupabaseSyncTransport's reading of failures, against the real Supabase
/// client and a fake server. Regression for the audit's offline findings: a
/// network failure while the access token needs refreshing is OFFLINE (keep
/// syncing with backoff, keep the outbox), never "sign in again"; nothing is
/// ever sent as anon; and a 42501 means "access turned off" only when the call
/// really ran as the signed-in person.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'sb_publishable_test';
const _userId = '00000000-0000-4000-8000-000000000001';

String _jwt(DateTime exp) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'sub': _userId, 'role': 'authenticated', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

String _session(String token) => jsonEncode({
  'access_token': token,
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'stored-refresh-token',
  'user': {
    'id': _userId,
    'aud': 'authenticated',
    'email': 'staff@arena.example',
    'created_at': '2026-10-01T00:00:00Z',
    'app_metadata': <String, Object>{},
    'user_metadata': <String, Object>{},
  },
});

class _Server {
  _Server({required this.refresh, required this.rpc});
  final Future<http.Response> Function(http.Request) refresh;
  final Future<http.Response> Function(http.Request) rpc;
  int rpcCalls = 0;
  int refreshCalls = 0;

  late final client = SupabaseClient(
    'http://backend.test',
    _key,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      if (req.url.path == '/auth/v1/token') {
        refreshCalls++;
        return refresh(req);
      }
      if (req.url.path.startsWith('/rest/v1/rpc/')) {
        rpcCalls++;
        return rpc(req);
      }
      return http.Response('not found', 404);
    }),
  );
  late final transport = SupabaseSyncTransport(client);

  Future<Object?> push() => transport.push('arena', const [], 'device');
}

http.Response _pgError(http.Request req, String code, String message) =>
    http.Response(
      jsonEncode({
        'code': code,
        'message': message,
        'hint': 'not a member',
        'details': null,
      }),
      403,
      request: req,
      headers: {'content-type': 'application/json'},
    );

void main() {
  final past = DateTime.now().subtract(const Duration(hours: 2));
  final future = DateTime.now().add(const Duration(hours: 1));
  Future<http.Response> neverCalled(http.Request _) async =>
      fail('not expected');

  test('no session: refused locally, nothing is sent as anon', () async {
    final s = _Server(refresh: neverCalled, rpc: neverCalled);
    await expectLater(
      s.push(),
      throwsA(
        isA<SyncAuthException>().having((e) => e.revoked, 'revoked', isFalse),
      ),
    );
    expect(s.rpcCalls, 0);
    await s.client.dispose();
  });

  // gotrue retries a refresh that cannot reach the server for about 10 s.
  test('offline while the access token needs refreshing: OFFLINE, the sign-in '
      'is kept', () async {
    final s = _Server(
      refresh: (_) async =>
          throw const SocketException('Network is unreachable'),
      rpc: neverCalled,
    );
    await s.client.auth.setInitialSession(_session(_jwt(past)));
    await expectLater(s.push(), throwsA(isA<SyncOfflineException>()));
    expect(
      s.client.auth.currentSession,
      isNotNull,
      reason: 'a network failure is not proof the session is invalid',
    );
    expect(s.rpcCalls, 0);
    await s.client.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
    'refresh token rejected by Auth: a sign-in problem, not "revoked"',
    () async {
      final s = _Server(
        refresh: (req) async => http.Response(
          jsonEncode({
            'code': 400,
            'error_code': 'refresh_token_not_found',
            'msg': 'Invalid Refresh Token: Refresh Token Not Found',
          }),
          400,
          request: req,
          headers: {'content-type': 'application/json'},
        ),
        rpc: neverCalled,
      );
      await s.client.auth.setInitialSession(_session(_jwt(past)));
      await expectLater(
        s.push(),
        throwsA(
          isA<SyncAuthException>().having((e) => e.revoked, 'revoked', isFalse),
        ),
      );
      expect(s.client.auth.currentSession, isNull, reason: 'gotrue dropped it');
      expect(s.rpcCalls, 0, reason: 'and nothing went out as anon');
      await s.client.dispose();
    },
  );

  test(
    'a 42501 for the signed-in person means access was turned off',
    () async {
      final s = _Server(
        refresh: neverCalled,
        rpc: (req) async => _pgError(req, '42501', 'forbidden'),
      );
      await s.client.auth.setInitialSession(_session(_jwt(future)));
      await expectLater(
        s.push(),
        throwsA(
          isA<SyncAuthException>().having((e) => e.revoked, 'revoked', isTrue),
        ),
      );
      await s.client.dispose();
    },
  );

  // The phone's clock is behind: gotrue thinks the token is still good, the
  // server says it expired. That used to stop sync with "Sign in again".
  http.Response jwtExpired(http.Request req) => http.Response(
    jsonEncode({
      'code': 'PGRST303',
      'message': 'JWT expired',
      'hint': null,
      'details': null,
    }),
    401,
    request: req,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> freshSession(http.Request req) async => http.Response(
    _session(_jwt(future)),
    200,
    request: req,
    headers: {'content-type': 'application/json'},
  );

  test('a token the server counts as expired is refreshed once and the call '
      'retried (slow phone clock)', () async {
    late final _Server s;
    s = _Server(
      refresh: freshSession,
      rpc: (req) async => s.refreshCalls == 0
          ? jwtExpired(req)
          : http.Response(
              jsonEncode({'results': <Object>[]}),
              200,
              request: req,
              headers: {'content-type': 'application/json'},
            ),
    );
    await s.client.auth.setInitialSession(_session(_jwt(future)));
    expect(await s.push(), isEmpty);
    expect(s.refreshCalls, 1);
    expect(s.rpcCalls, 2);
    expect(s.client.auth.currentSession, isNotNull);
    await s.client.dispose();
  });

  test('still refused after a fresh token: sign in again (not "revoked"), '
      'and only one retry', () async {
    final s = _Server(refresh: freshSession, rpc: (req) async => jwtExpired(req));
    await s.client.auth.setInitialSession(_session(_jwt(future)));
    await expectLater(
      s.push(),
      throwsA(
        isA<SyncAuthException>().having((e) => e.revoked, 'revoked', isFalse),
      ),
    );
    expect(s.refreshCalls, 1);
    expect(s.rpcCalls, 2);
    await s.client.dispose();
  });

  test('the refresh for a refused token cannot reach Auth: OFFLINE, the '
      'sign-in is kept', () async {
    final s = _Server(
      refresh: (_) async =>
          throw const SocketException('Network is unreachable'),
      rpc: (req) async => jwtExpired(req),
    );
    await s.client.auth.setInitialSession(_session(_jwt(future)));
    await expectLater(s.push(), throwsA(isA<SyncOfflineException>()));
    expect(s.client.auth.currentSession, isNotNull);
    expect(s.rpcCalls, 1);
    await s.client.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('my_arenas at start-up gets the same single refresh-and-retry', () async {
    late final _Server s;
    s = _Server(
      refresh: freshSession,
      rpc: (req) async => s.refreshCalls == 0
          ? jwtExpired(req)
          : http.Response(
              '[]',
              200,
              request: req,
              headers: {'content-type': 'application/json'},
            ),
    );
    await s.client.auth.setInitialSession(_session(_jwt(future)));
    expect(
      await rpcWithFreshToken(
        s.client,
        'my_arenas',
        null,
        timeout: const Duration(seconds: 5),
      ),
      isEmpty,
    );
    expect(s.refreshCalls, 1);
    await s.client.dispose();
  });

  test('a network failure on the call itself is OFFLINE', () async {
    final s = _Server(
      refresh: neverCalled,
      rpc: (_) async => throw const SocketException('Connection reset'),
    );
    await s.client.auth.setInitialSession(_session(_jwt(future)));
    await expectLater(s.push(), throwsA(isA<SyncOfflineException>()));
    expect(s.client.auth.currentSession, isNotNull);
    await s.client.dispose();
  });
}
