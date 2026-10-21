/// The network side of sync, behind an interface so the engine can be tested
/// without a server and the Supabase client stays at the edge.
library;

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One outbox op as sync_push receives it.
typedef OutgoingOp = ({String opId, String kind, Map<String, dynamic> payload});

/// The server's verdict on one op.
class OpResult {
  const OpResult({
    required this.opId,
    required this.status,
    this.result,
    this.error,
    this.detail,
    this.replayed = false,
  });

  final String opId;

  /// applied | rejected | retry
  final String status;
  final Map<String, dynamic>? result;
  final String? error;
  final String? detail;
  final bool replayed;

  bool get adjusted => result?['adjusted'] == true;

  factory OpResult.fromJson(Map<String, dynamic> j) => OpResult(
    opId: j['op_id'] as String,
    status: j['status'] as String,
    result: j['result'] == null
        ? null
        : Map<String, dynamic>.from(j['result'] as Map),
    error: j['error'] as String?,
    detail: j['detail'] as String?,
    replayed: j['replayed'] == true,
  );
}

class PullPage {
  const PullPage({
    required this.cursor,
    required this.hasMore,
    required this.changes,
    this.serverTime,
    this.scope,
  });
  final String cursor;
  final bool hasMore;
  final List<Map<String, dynamic>> changes;
  final DateTime? serverTime;

  /// The feeds this member may not receive (customers / money / coupons, by
  /// permission); null from a server that does not narrow the feed.
  final List<String>? scope;

  factory PullPage.fromJson(Map<String, dynamic> j) => PullPage(
    cursor: j['cursor'] as String,
    hasMore: j['has_more'] == true,
    changes: [
      for (final c in j['changes'] as List) Map<String, dynamic>.from(c as Map),
    ],
    serverTime: j['server_time'] == null
        ? null
        : DateTime.parse(j['server_time'] as String).toUtc(),
    scope: j['scope'] is List
        ? [for (final s in j['scope'] as List) s as String]
        : null,
  );
}

/// A whole entity as the server holds it ({t, r} rows, empty = never had it).
typedef EntityRows = ({
  String type,
  String id,
  List<Map<String, dynamic>> rows,
});

/// The device cannot reach the server (no network, DNS, TLS, timeout). Safe to
/// retry later; nothing is lost — the outbox keeps every op.
class SyncOfflineException implements Exception {
  SyncOfflineException(this.cause);
  final Object cause;
  @override
  String toString() => 'offline: $cause';
}

/// The signed-in account cannot sync: the session expired and could not be
/// refreshed, or the person is no longer an active member of the arena.
/// Sync stops until someone signs in again; the outbox is kept.
class SyncAuthException implements Exception {
  SyncAuthException(this.message, {this.revoked = false});
  final String message;

  /// Access was turned off (not just an expired sign-in).
  final bool revoked;
  @override
  String toString() => 'auth: $message';
}

abstract interface class SyncTransport {
  Future<List<OpResult>> push(
    String arenaId,
    List<OutgoingOp> ops,
    String deviceId,
  );
  Future<PullPage> pull(String arenaId, String cursor, {int limit});
  Future<List<EntityRows>> fetchEntities(
    String arenaId,
    List<({String type, String id})> refs,
  );
}

/// [SyncTransport] over the Supabase RPCs (sync_push / sync_pull /
/// sync_fetch_entity). Only the anon key and the signed-in user's own JWT are
/// ever used — the service-role key never exists in the app.
/// Whether the API refused the access token itself (expired or invalid JWT).
bool isTokenRejected(PostgrestException e) =>
    e.code == 'PGRST301' ||
    e.code == 'PGRST303' ||
    e.message.toLowerCase().contains('jwt');

/// Calls [fn]; if the API refuses the access token, refreshes the sign-in once
/// and calls again. Auth decides "expired" by THIS device's clock, so a phone
/// running a few minutes slow keeps sending a token the server already counts
/// as expired — refreshing gets one that is valid by the server's clock. A
/// refused refresh surfaces as an [AuthException]; no network as
/// [AuthRetryableFetchException]; a second token refusal as the
/// [PostgrestException] — the callers classify those.
Future<Object?> rpcWithFreshToken(
  SupabaseClient client,
  String fn,
  Map<String, dynamic>? params, {
  required Duration timeout,
}) async {
  try {
    return await client.rpc(fn, params: params).timeout(timeout);
  } on PostgrestException catch (e) {
    if (!isTokenRejected(e)) rethrow;
    await client.auth.refreshSession().timeout(timeout);
    return await client.rpc(fn, params: params).timeout(timeout);
  }
}

class SupabaseSyncTransport implements SyncTransport {
  SupabaseSyncTransport(
    this._client, {
    this.timeout = const Duration(seconds: 20),
  });
  final SupabaseClient _client;
  final Duration timeout;

  Future<Object?> _rpc(String fn, Map<String, dynamic> params) async {
    // Never call as anon: without a session the request would carry only the
    // publishable key, be refused (42501) and read as "access turned off".
    if (_client.auth.currentSession == null) {
      throw SyncAuthException('Signed out');
    }
    try {
      return await rpcWithFreshToken(_client, fn, params, timeout: timeout);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        // Revoked only if we really called as the signed-in person; if the
        // session vanished meanwhile (refresh refused) it is a sign-in problem.
        throw SyncAuthException(
          e.hint ?? e.message,
          revoked: _client.auth.currentSession != null,
        );
      }
      if (isTokenRejected(e)) throw SyncAuthException(e.message);
      rethrow;
    } on AuthRetryableFetchException catch (e) {
      // The access token needed refreshing and Auth could not be reached: the
      // device is offline, the sign-in is still good. Keep syncing with backoff.
      throw SyncOfflineException(e);
    } on AuthException catch (e) {
      throw SyncAuthException(e.message);
    } on SocketException catch (e) {
      throw SyncOfflineException(e);
    } on TimeoutException catch (e) {
      throw SyncOfflineException(e);
    } on HandshakeException catch (e) {
      throw SyncOfflineException(e);
    } on HttpException catch (e) {
      throw SyncOfflineException(e);
    } on Exception catch (e) {
      // http.ClientException and friends: no response from the server.
      if (e.toString().contains('ClientException')) {
        throw SyncOfflineException(e);
      }
      rethrow;
    }
  }

  @override
  Future<List<OpResult>> push(
    String arenaId,
    List<OutgoingOp> ops,
    String deviceId,
  ) async {
    final out = await _rpc('sync_push', {
      'p_arena': arenaId,
      'p_device': deviceId,
      'p_ops': [
        for (final o in ops)
          {'op_id': o.opId, 'kind': o.kind, 'payload': o.payload},
      ],
    }) as Map;
    return [
      for (final r in out['results'] as List)
        OpResult.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  @override
  Future<PullPage> pull(
    String arenaId,
    String cursor, {
    int limit = 2000,
  }) async {
    final out = await _rpc('sync_pull', {
      'p_arena': arenaId,
      'p_cursor': cursor,
      'p_limit': limit,
    }) as Map;
    return PullPage.fromJson(Map<String, dynamic>.from(out));
  }

  @override
  Future<List<EntityRows>> fetchEntities(
    String arenaId,
    List<({String type, String id})> refs,
  ) async {
    final out = await _rpc('sync_fetch_entity', {
      'p_arena': arenaId,
      'p_refs': [
        for (final r in refs) {'type': r.type, 'id': r.id},
      ],
    }) as List;
    return [
      for (final e in out)
        (
          type: (e as Map)['ref']['type'] as String,
          id: e['ref']['id'] as String,
          rows: [
            for (final r in e['rows'] as List)
              Map<String, dynamic>.from(r as Map),
          ],
        ),
    ];
  }
}
