/// Is the sign-in this device kept still good enough to call the server with?
///
/// supabase_flutter restores the stored session as it was saved — often with
/// an expired access token — and refreshes it in the background. If the server
/// refuses that refresh (e.g. `refresh_token_not_found`: the login was signed
/// out elsewhere, or the backend was reset), gotrue drops the session, and every
/// API call after that goes out with only the publishable key: as `anon`, which
/// may call nothing (`permission denied for function my_arenas`). So the app
/// asks first, and sends the person to sign in rather than calling as `anon`.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum StoredSession {
  /// Usable now (refreshed if it had to be).
  valid,

  /// The server could not be reached to refresh it. The sign-in is kept, so the
  /// app can open the last arena from disk (offline-first) and retry later.
  offline,

  /// Nothing stored, or the server refused it. The person must sign in again;
  /// unsent work stays in their database file for when they do.
  signInNeeded,
}

Future<StoredSession> checkStoredSession(
  GoTrueClient auth, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (auth.currentSession == null) return StoredSession.signInNeeded;
  try {
    // Refreshes an expired session, sharing any refresh already in flight.
    final session = await auth.getSession().timeout(timeout);
    return session == null ? StoredSession.signInNeeded : StoredSession.valid;
  } on TimeoutException {
    // Auth did not answer in time (a weak or captive network). The sign-in is
    // kept and the refresh carries on in the background: start offline rather
    // than leave the person on a spinner.
    return auth.currentSession == null
        ? StoredSession.signInNeeded
        : StoredSession.offline;
  } on AuthRetryableFetchException {
    return auth.currentSession == null
        ? StoredSession.signInNeeded
        : StoredSession.offline;
  } on AuthException {
    // Refused by the server: gotrue has already removed the session.
    return StoredSession.signInNeeded;
  }
}

/// What a failed start-up call (e.g. `my_arenas`) means for the stored sign-in.
enum StartupFailure {
  /// The server could not be reached — including an access-token refresh that
  /// failed for lack of network. Keep the sign-in and the local arena database;
  /// open the last arena from disk (offline-first) and retry later.
  offline,

  /// The sign-in itself was rejected: Auth refused the refresh token (gotrue has
  /// dropped the session) or the API rejected the token. Only this clears the
  /// stored sign-in; unsent work stays in the person's database file.
  signInNeeded,

  /// Signed in and reachable, but the server refused this call for another
  /// reason (e.g. a misconfigured backend). Keep the sign-in; show the error
  /// with a retry.
  serverRefused,
}

/// Classifies [error] from a start-up call. [hasSession] is whether gotrue
/// still holds a session after the failure — it removes it only when the
/// server refused the refresh, never for a network failure. A network error is
/// never read as proof that the session is invalid.
StartupFailure classifyStartupFailure(
  Object error, {
  required bool hasSession,
}) {
  if (!hasSession) return StartupFailure.signInNeeded;
  // Before AuthException: the retryable kind is a subclass of it.
  if (error is AuthRetryableFetchException) return StartupFailure.offline;
  if (error is AuthException) return StartupFailure.signInNeeded;
  if (error is PostgrestException) {
    if (error.code == 'PGRST301' || error.code == 'PGRST303') {
      return StartupFailure.signInNeeded; // the API rejected the token itself
    }
    // A 3-digit code is the HTTP status of a non-JSON reply (gateway down);
    // 5-character codes are Postgres SQLSTATEs (e.g. 42501), never "offline".
    final code = error.code ?? '';
    final status = code.length == 3 ? int.tryParse(code) : null;
    if (status != null && status >= 500) return StartupFailure.offline;
    return StartupFailure.serverRefused;
  }
  // SocketException, TimeoutException, TLS and HTTP client errors: no answer.
  return StartupFailure.offline;
}
