/// The staff app's sign-in decisions, kept out of the widgets so they can be
/// tested against a real server (test/sync/staff_login_test.dart) as well as
/// with fakes: which arenas a login belongs to (my_arenas), whether the person
/// may work in the arena a device database holds, and what to tell them when
/// something fails — never a raw exception, token or SQL error.
library;

import 'dart:async';
import 'dart:io';

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_transport.dart' show rpcWithFreshToken;
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One membership as my_arenas() reports it.
typedef Membership = ({
  String arenaId,
  String arenaName,
  String name,
  bool active,
});

/// my_arenas() rows → memberships. A row the app cannot read (no arena id) is
/// left out rather than failing the whole list; a missing name or flag never
/// throws (an absent `active` is read as off: access is never assumed).
List<Membership> parseMemberships(Object? rows) {
  if (rows is! List) return const [];
  return [
    for (final r in rows)
      if (r is Map && r['arena_id'] is String)
        (
          arenaId: r['arena_id'] as String,
          arenaName: (r['arena_name'] as String?) ?? 'Arena',
          name: (r['name'] as String?) ?? '',
          active: r['active'] == true,
        ),
  ];
}

/// The device database of one person in one arena. Every (arena, person) has
/// its own file, so after a sign-out another login never sees — or pushes —
/// the previous person's data or unsent work.
String cloudDbPath(String documentsPath, String arenaId, String userId) =>
    '$documentsPath/arena_ops_cloud_${arenaId}_$userId.sqlite';

/// The signed-in login's memberships, from the server. A token the server
/// counts as expired (a phone clock running slow) is refreshed and the call
/// retried once, rather than read as a sign-in to throw away; no answer within
/// [timeout] is a [TimeoutException] — offline, so the last arena opens from
/// disk instead of the start-up hanging.
Future<List<Membership>> fetchMemberships(
  SupabaseClient client, {
  Duration timeout = const Duration(seconds: 10),
}) async => parseMemberships(
  await rpcWithFreshToken(client, 'my_arenas', null, timeout: timeout),
);

/// The arena to open without asking: the only active one, or — with several —
/// the one this person last worked in on this device ([lastArenaId]) while it
/// is still active. Null: show the list (no active arena, or several and no
/// usable last one).
Membership? arenaToOpen(List<Membership> memberships, String? lastArenaId) {
  final active = memberships.where((a) => a.active).toList();
  if (active.length == 1) return active.single;
  return active.where((a) => a.arenaId == lastArenaId).firstOrNull;
}

/// What an arena's device database says about the signed-in person.
sealed class ArenaAccess {
  const ArenaAccess();
}

/// May work here, with these server-given permissions.
final class AccessGranted extends ArenaAccess {
  const AccessGranted(this.user);
  final AppUser user;
}

/// Their profile here is turned off.
final class AccessTurnedOff extends ArenaAccess {
  const AccessTurnedOff();
}

/// Their profile has not reached this device (never downloaded).
final class AccessNotOnDevice extends ArenaAccess {
  const AccessNotOnDevice();
}

/// The person's access as the synced staff list in [db] has it.
Future<ArenaAccess> localAccess(AppDatabase db, String userId) async {
  final me = await (db.select(
    db.users,
  )..where((t) => t.id.equals(userId))).getSingleOrNull();
  if (me == null) return const AccessNotOnDevice();
  if (!me.active) return const AccessTurnedOff();
  return AccessGranted(
    AppUser(id: me.id, name: me.name, perms: Permission.parse(me.perms)),
  );
}

/// The check before an arena opens. When the server has just confirmed an
/// active membership ([confirmedOnline]) but this device's copy of the staff
/// list says otherwise — an older copy, from before an invitation was accepted
/// or access was turned back on — [sync] once and look again, so a valid
/// member is never told their access is off. Offline, the device's copy is
/// all there is.
Future<ArenaAccess> confirmAccess({
  required AppDatabase db,
  required String userId,
  required bool confirmedOnline,
  required Future<void> Function() sync,
}) async {
  final first = await localAccess(db, userId);
  if (first is AccessGranted || !confirmedOnline) return first;
  await sync();
  return localAccess(db, userId);
}

// -------------------------------------------------------------- messages

/// No answer from the server (no network, or the server is down).
const offlineMessage =
    "Can't reach the server. Check the device's connection, then try again.";

/// Why a sign-in failed, in words for the person at the counter.
String signInFailureMessage(Object error) {
  if (error is AuthRetryableFetchException) return offlineMessage;
  if (error is AuthException) {
    final code = error.code ?? '';
    final text = error.message.toLowerCase();
    if (code == 'invalid_credentials' ||
        text.contains('invalid login credentials')) {
      return "That e-mail and password don't match a login on this server. "
          'Invited? Open the invitation e-mail first and choose your '
          'password there, then sign in here with it.';
    }
    if (code == 'email_not_confirmed' || text.contains('email not confirmed')) {
      return 'This e-mail address is not confirmed yet. Open the link in your '
          'invitation e-mail, then sign in.';
    }
    if (code == 'user_banned') {
      return 'This login is blocked. Ask the owner.';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        error.statusCode == '429') {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    final status = int.tryParse(error.statusCode ?? '');
    if (status != null && status >= 500) return offlineMessage;
    return 'Sign-in failed${code.isEmpty ? '' : ' ($code)'}. Try again; if it '
        'keeps failing, tell the owner.';
  }
  if (_isNetwork(error)) return offlineMessage;
  return 'Sign-in failed. Try again; if it keeps failing, tell the owner.';
}

/// Why the arena list could not be read from a reachable server.
String arenaListFailureMessage(Object error) {
  if (error is PostgrestException) {
    if (error.code == 'PGRST202') {
      // The function is missing: the app points at a server without the
      // database update the staff app needs (e.g. a project not migrated).
      return "This server isn't set up for the staff app yet (a database "
          'update is missing). Tell the owner.';
    }
    if (error.code == '42501') {
      return 'The server refused to list your arenas. Sign in again; if it '
          'keeps happening, ask the owner to check your access.';
    }
    final code = error.code;
    return "Couldn't load your arenas${code == null ? '' : ' ($code)'}. "
        'Try again.';
  }
  return "Couldn't load your arenas. Try again.";
}

/// Why the first download of an arena did not finish.
String firstDownloadFailureMessage(SyncStatus status, String arenaName) {
  if (status.accessRevoked) {
    return 'Your access to $arenaName is turned off. Ask the owner.';
  }
  return switch (status.state) {
    SyncState.offline =>
      '$arenaName must download once before it can open here, and the '
          "server can't be reached. Check the connection, then try again.",
    SyncState.authProblem => 'Your sign-in has expired. Sign in again.',
    _ =>
      "$arenaName couldn't be downloaded. Try again; if it keeps failing, "
          'tell the owner.',
  };
}

/// "Local test server (127.0.0.1:54431)" or "abcd.supabase.co": which backend
/// this build signs in to, so a login made on another server is easy to spot.
String serverLabel(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (host.isEmpty) return url;
  const local = {'127.0.0.1', 'localhost', '10.0.2.2'};
  return local.contains(host)
      ? 'Local test server (${uri!.authority})'
      : uri!.authority;
}

/// No answer from the server: sockets, timeouts, TLS, and http's
/// ClientException (matched by name, as in sync_transport.dart: `http` is not
/// a dependency of the app itself).
bool _isNetwork(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e.toString().contains('ClientException');
