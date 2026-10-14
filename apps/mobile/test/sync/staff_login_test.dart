/// The staff login, end to end on one local Supabase stack, for the person the
/// dashboard invited by e-mail in tool/sync_it.sh phase 1 (they accepted from
/// the e-mailed link and chose their password there; perms: start). Each step
/// runs what the floor app's CloudRoot runs — fetchMemberships, the per-person
/// database file, the first download, confirmAccess — against the real server:
///
/// * a wrong password is refused (and worded for the counter); the right one
///   signs in; the login has exactly one, active membership — no Create Arena;
/// * the first download opens the invited arena with the server's permissions
///   (staff, not owner: no Money / Reports / Today);
/// * the server refuses what those permissions do not allow;
/// * permissions the owner changes reach the device; a legitimate session is
///   started, billed and paid, and the owner sees it on the shared backend;
/// * a restart reopens the same file without a new download or a duplicate
///   op; an expired sign-in asks for a new one; access turned off is refused by
///   the server and turned back on works again; another arena stays closed;
/// * another login on the same device gets its own file.
///
/// Skipped (not failed) outside tool/sync_it.sh.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:arena_ops/app/router/app_router.dart';
import 'package:arena_ops/app/sync/staff_access.dart';
import 'package:arena_ops/app/sync/stored_session.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:uuid/uuid.dart';

import '../support/sim_device.dart';

/// One staff phone running the floor app's start-up path (no widgets).
class _FloorPhone {
  _FloorPhone(this.client, this.documents);

  final SupabaseClient client;
  final String documents;
  final Clock clock = const SystemClock();
  AppDatabase? db;
  SyncEngine? engine;
  SyncRecorder? recorder;
  String? arenaId;

  String get userId => client.auth.currentUser!.id;

  /// A client configured like the app's (PKCE flow), signed in with [password].
  static Future<_FloorPhone> signIn(
    String url,
    String key,
    String email,
    String password,
    String documents,
  ) async {
    final client = _client(url, key);
    await client.auth.signInWithPassword(email: email, password: password);
    return _FloorPhone(client, documents);
  }

  /// The app after a restart: the stored sign-in (its refresh token) put back.
  static Future<_FloorPhone> restore(
    String url,
    String key,
    String refreshToken,
    String documents,
  ) async {
    final client = _client(url, key);
    await client.auth.setSession(refreshToken);
    return _FloorPhone(client, documents);
  }

  static SupabaseClient _client(String url, String key) => SupabaseClient(
    url,
    key,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  /// What CloudRoot._open does before showing the floor: this person's own
  /// file, the first download if it is new, then the access check.
  Future<ArenaAccess> open(String arena, {bool confirmedOnline = true}) async {
    arenaId = arena;
    final file = File(cloudDbPath(documents, arena, userId));
    final opened = AppDatabase(NativeDatabase(file));
    db = opened;
    recorder = SyncRecorder(opened, actor: () => userId, clock: clock);
    final sync = SyncEngine(
      db: opened,
      transport: SupabaseSyncTransport(client),
      arenaId: arena,
      clock: clock,
    );
    engine = sync;
    final cursor = await (opened.select(
      opened.syncMeta,
    )..where((t) => t.key.equals(SyncEngine.cursorKey))).getSingleOrNull();
    if (cursor == null) {
      final first = await sync.syncNow();
      if (first.endedIn != SyncState.synced) {
        throw StateError(firstDownloadFailureMessage(sync.status, arena));
      }
    }
    return confirmAccess(
      db: opened,
      userId: userId,
      confirmedOnline: confirmedOnline,
      sync: () => sync.syncNow(),
    );
  }

  LocalSessionRepository get sessions =>
      LocalSessionRepository(db!, clock, recorder);
  LocalCustomerRepository get customers =>
      LocalCustomerRepository(db!, clock, recorder);
  LocalCatalogRepository get catalog =>
      LocalCatalogRepository(db!, clock, recorder);

  Future<void> close() async {
    await engine?.dispose();
    await db?.close();
    engine = null;
    db = null;
  }

  Future<void> dispose() async {
    await close();
    await client.dispose();
  }
}

void main() {
  final url = Platform.environment['AO_SUPABASE_URL'];
  final key = Platform.environment['AO_SUPABASE_ANON_KEY'];
  final password = Platform.environment['AO_IT_PASSWORD'];
  final ownerEmail = Platform.environment['AO_IT_OWNER_EMAIL'];
  final staffEmail = Platform.environment['AO_IT_STAFF_EMAIL'];
  final invitee = Platform.environment['AO_IT_INVITEE_EMAIL'];
  final arenaId = Platform.environment['AO_IT_ARENA'];
  final skip =
      (url == null ||
          key == null ||
          password == null ||
          invitee == null ||
          arenaId == null)
      ? 'local Supabase stack not configured (run tool/sync_it.sh)'
      : null;

  late Directory documents;
  late SimDevice owner;
  late _FloorPhone phone;

  setUpAll(() async {
    if (skip != null) return;
    documents = Directory.systemTemp.createTempSync('ao-staff-login-');
    owner = await SimDevice.signIn('owner', url!, key!, ownerEmail!);
    owner.bind(arenaId!);
    await owner.sync();
  });

  tearDownAll(() async {
    if (skip != null) return;
    await owner.close();
    documents.deleteSync(recursive: true);
  });

  /// staff.update from the owner's device (the dashboard's Users page sends
  /// the same op).
  Future<void> ownerSets(String userId, {Set<Permission>? perms, bool? active}) async {
    await owner.sync();
    final row = await (owner.db.select(
      owner.db.users,
    )..where((t) => t.id.equals(userId))).getSingle();
    await LocalUserRepository(owner.db, owner.clock, owner.recorder).upsert(
      AppUser(
        id: row.id,
        name: row.name,
        perms: perms ?? Permission.parse(row.perms),
        active: active ?? row.active,
      ),
    );
    expect((await owner.sync()).rejected, 0);
  }

  test('a wrong password is refused, in words that say what to do', () async {
    final client = SupabaseClient(url!, key!,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    final error = await client.auth
        .signInWithPassword(email: invitee!, password: '$password-wrong')
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<AuthException>());
    expect(client.auth.currentSession, isNull);
    expect(signInFailureMessage(error!), contains("don't match a login"));
  }, skip: skip);

  test('the invited person signs in and opens the arena they were invited to, '
      'as staff', () async {
    phone = await _FloorPhone.signIn(url!, key!, invitee!, password!, documents.path);

    final memberships = await fetchMemberships(phone.client);
    expect(memberships.where((m) => m.arenaId == arenaId), hasLength(1),
        reason: 'accepted once; the retried accept made no second membership');
    expect(memberships.single.active, isTrue);

    final access = await phone.open(arenaId!);
    expect(access, isA<AccessGranted>());
    final me = (access as AccessGranted).user;
    expect(me.perms, {Permission.start}, reason: 'what the invitation granted');
    expect(me.isOwner, isFalse);
    // The floor app's tabs for that user: no owner screens.
    expect(defaultPathFor(me), '/floor');
    expect(
      [for (final t in AppTab.all) if (t.visibleFor(me)) t.label],
      ['Floor', 'More'],
    );
    // The arena's catalog came down with the first download.
    expect(await phone.db!.select(phone.db!.resources).get(), isNotEmpty);
  }, skip: skip);

  test('the server refuses what those permissions do not allow', () async {
    final transport = SupabaseSyncTransport(phone.client);
    final results = await transport.push(arenaId!, [
      (
        opId: const Uuid().v4(),
        kind: 'payment.record',
        payload: {
          'scope': 'single',
          'parent_id': const Uuid().v4(),
          'payment_id': const Uuid().v4(),
          'amount_paise': 100,
          'method': 'cash',
          'is_refund': false,
        },
      ),
      (
        opId: const Uuid().v4(),
        kind: 'rate.upsert',
        payload: {
          'activity_code': 'PS5',
          'band': 'standard',
          'controller_count': 1,
          'unit_minutes': 60,
          'price_paise': 1,
        },
      ),
    ], 'it-staff-login');
    expect([for (final r in results) r.error], ['forbidden', 'forbidden']);
    // Bills are not readable directly without bill / money / reports (RLS).
    expect(await phone.client.from('payments').select('id').limit(1), isEmpty);
  }, skip: skip);

  test('the owner grants Bill; the device follows; a legitimate session is '
      'started, billed and paid, and the owner sees it', () async {
    await ownerSets(phone.userId, perms: {Permission.start, Permission.bill});
    addTearDown(() => ownerSets(phone.userId, perms: {Permission.start}));
    await phone.engine!.syncNow();
    final me = await localAccess(phone.db!, phone.userId);
    expect((me as AccessGranted).user.perms, {Permission.start, Permission.bill});

    // A station with no session on it that sells the lounge (no pads).
    final busy = {
      for (final s in await (phone.db!.select(phone.db!.sessionSegments)
            ..where((t) => t.endedAt.isNull()))
          .get())
        s.resourceId,
    };
    final lounge = (await phone.catalog.resources())
        .where((r) => r.activityCodes.contains('LOUNGE') && !busy.contains(r.id))
        .first;
    final guest = (await phone.customers.createGuest()).id;
    final startedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final started = await phone.sessions.start(StartSessionCommand(
      customerId: guest,
      startedAt: startedAt,
      scheduledEndAt: startedAt.add(const Duration(hours: 1)),
      snapshot: await phone.catalog.currentSnapshot(),
      resourceId: lounge.id,
      resourceName: lounge.name,
      activityCode: 'LOUNGE',
    ));
    expect(started.isOk, isTrue, reason: '${started.failureOrNull?.message}');
    final id = started.valueOrNull!.id;
    final endAt = startedAt.add(const Duration(minutes: 25));
    final s = (await phone.sessions.getById(id))!;
    final bill = const SegmentBilling().bill(
      snapshot: s.snapshot,
      segments: await phone.sessions.segmentsFor(id),
      openEndAt: endAt,
    );
    final ended = await phone.sessions.end(EndSessionCommand(
      sessionId: id,
      actualEndedAt: endAt,
      charges: bill.charges,
      billedAmountPaise: bill.total.value,
    ));
    expect(ended.isOk, isTrue, reason: '${ended.failureOrNull?.message}');
    final amount = ended.valueOrNull!.billedAmountPaise!;
    final paid = await phone.sessions.recordPayment(RecordPaymentCommand(
      sessionId: id,
      amountPaise: amount,
      method: PaymentMethod.cash,
      requestId: 'it-login-pay-$id',
    ));
    expect(paid.isOk, isTrue, reason: '${paid.failureOrNull?.message}');
    final pushed = await phone.engine!.syncNow();
    expect(pushed.rejected, 0);

    // The shared backend, as the owner (dashboard Sales reads these rows).
    final row = await owner.client
        .from('sessions')
        .select('status, billed_amount_paise, payment_status')
        .eq('id', id)
        .single();
    expect(row, {
      'status': 'completed',
      'billed_amount_paise': amount,
      'payment_status': 'paid',
    });
    final payments =
        await owner.client.from('payments').select('id').eq('session_id', id);
    expect(payments, hasLength(1));
  }, skip: skip);

  test('a restart reopens the same file: no new download, no op sent twice',
      () async {
    final stored = phone.client.auth.currentSession!.refreshToken!;
    final applied = await (phone.db!.select(phone.db!.syncOutbox)
          ..where((t) => t.status.equals(OutboxStatus.applied)))
        .get();
    await phone.dispose();

    phone = await _FloorPhone.restore(url!, key!, stored, documents.path);
    expect(await checkStoredSession(phone.client.auth), StoredSession.valid);
    expect((await fetchMemberships(phone.client)).single.active, isTrue);
    expect(await phone.open(arenaId!), isA<AccessGranted>());

    // A lost answer resent with the same op ids: replayed, never applied twice.
    final replay = await SupabaseSyncTransport(phone.client).push(arenaId, [
      for (final op in applied)
        (opId: op.opId, kind: op.kind, payload: <String, dynamic>{}),
    ], 'it-staff-login');
    expect(replay.every((r) => r.status == 'applied'), isTrue);
    final report = await phone.engine!.syncNow();
    expect(report.endedIn, SyncState.synced);
    expect(
      await (phone.db!.select(phone.db!.syncOutbox)
            ..where((t) => t.status.equals(OutboxStatus.pending)))
          .get(),
      isEmpty,
    );
  }, skip: skip);

  test('access turned off: refused by the server, the device stops; turned '
      'back on: opens again', () async {
    await ownerSets(phone.userId, active: false);
    var restored = false;
    addTearDown(() async {
      if (!restored) await ownerSets(phone.userId, active: true);
    });

    final r = await phone.engine!.syncNow();
    expect(r.endedIn, SyncState.authProblem);
    expect(phone.engine!.status.accessRevoked, isTrue);
    expect((await fetchMemberships(phone.client)).single.active, isFalse,
        reason: 'the arena list shows it turned off: it cannot be opened');
    expect(await phone.client.from('sessions').select('id').limit(1), isEmpty,
        reason: 'no arena data for an inactive membership (RLS)');

    await ownerSets(phone.userId, active: true);
    restored = true;
    await phone.close();
    expect((await fetchMemberships(phone.client)).single.active, isTrue);
    expect(await phone.open(arenaId!), isA<AccessGranted>());
    expect((await phone.engine!.syncNow()).endedIn, SyncState.synced);
  }, skip: skip);

  test('another arena stays closed to this login', () async {
    final other = await SupabaseSyncTransport(phone.client)
        .pull(const Uuid().v4(), '0')
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(other, isA<SyncAuthException>());
  }, skip: skip);

  test('an expired sign-in the server no longer accepts asks for a new one '
      'instead of calling as anon', () async {
    // A second device of the same person: its stored sign-in, then that
    // session signed out on the server (signed out elsewhere, or reset).
    final other = await _FloorPhone.signIn(
      url!, key!, invitee!, password!, documents.path);
    final saved = jsonEncode(other.client.auth.currentSession!.toJson());
    await other.client.auth.signOut(); // revokes that session's refresh token
    await other.dispose();

    final restarted = SupabaseClient(url, key,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(restarted.dispose);
    // What supabase_flutter does at start with the stored session …
    await restarted.auth.recoverSession(saved);
    // … and once its access token expires, the refresh: the server refuses it.
    final refused = await restarted.auth
        .refreshSession()
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(refused, isA<AuthException>());
    expect(restarted.auth.currentSession, isNull, reason: 'gotrue dropped it');
    expect(await checkStoredSession(restarted.auth), StoredSession.signInNeeded);
    expect(
      classifyStartupFailure(refused!, hasSession: false),
      StartupFailure.signInNeeded,
      reason: 'sign in again; never call my_arenas as anon',
    );
    // The phone's own sign-in was untouched.
    expect(await checkStoredSession(phone.client.auth), StoredSession.valid);
  }, skip: skip);

  test('another login on this device gets its own file, never the previous '
      "person's", () async {
    final mine = cloudDbPath(documents.path, arenaId!, phone.userId);
    await phone.client.auth.signOut();
    await phone.dispose();
    expect(File(mine).existsSync(), isTrue, reason: 'unsent work stays on disk');

    final other = await _FloorPhone.signIn(
      url!, key!, staffEmail!, password!, documents.path);
    addTearDown(other.dispose);
    expect(cloudDbPath(documents.path, arenaId, other.userId), isNot(mine));
    expect(await other.open(arenaId), isA<AccessGranted>());
    expect(
      await (other.db!.select(other.db!.syncOutbox)).get(),
      isEmpty,
      reason: 'a fresh file: nothing of the previous login',
    );
  }, skip: skip);
}
