/// Cross-app and Realtime checks against the LOCAL Supabase stack, nothing
/// mocked. Run through `bash tool/sync_it.sh`, which provisions throw-away
/// logins and arenas and runs the dashboard (Angular) phases around this file.
///
///  * private arena channel: a member joins it, a login of another arena is
///    refused (realtime.messages policies);
///  * a committed push on one device reaches another device as a broadcast
///    nudge carrying only the applied op kinds;
///  * another arena can neither read nor write this arena;
///  * dashboard → floor: the game and station availability the owner set on
///    the dashboard (phase 1, written to $AO_IT_HANDOFF/dashboard.json) reach
///    the staff device, and the session the staff run is handed back for the
///    dashboard phase 2 ($AO_IT_HANDOFF/floor.json).
/// Skipped (not failed) without the environment, so `flutter test` stays offline.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arena_ops/data/sync/realtime_sync.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:uuid/uuid.dart';

import '../support/sim_device.dart';

/// Joins `arena:<id>` as a private channel and reports how the join ended.
/// The channel stays open (it is the listener); [_leaveAll] removes them.
Future<RealtimeSubscribeStatus> _join(
  SupabaseClient client,
  String arenaId, {
  List<Map<String, dynamic>>? broadcasts,
}) async {
  await client.realtime.setAuth(client.auth.currentSession!.accessToken);
  final done = Completer<RealtimeSubscribeStatus>();
  final channel = client.channel(
    'arena:$arenaId',
    opts: const RealtimeChannelConfig(private: true),
  );
  if (broadcasts != null) {
    channel.onBroadcast(event: 'sync', callback: broadcasts.add);
  }
  channel.subscribe((status, [error]) {
    if (!done.isCompleted && status != RealtimeSubscribeStatus.closed) {
      done.complete(status);
    }
  });
  return done.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => RealtimeSubscribeStatus.timedOut,
  );
}

Future<void> _until(
  Future<bool> Function() ok, {
  Duration within = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(within);
  while (DateTime.now().isBefore(end)) {
    if (await ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('condition not met within $within');
}

Future<void> _leaveAll(SupabaseClient client) async {
  for (final c in [...client.getChannels()]) {
    await client.removeChannel(c);
  }
}

void main() {
  final env = Platform.environment;
  final url = env['AO_SUPABASE_URL'];
  final key = env['AO_SUPABASE_ANON_KEY'];
  final arenaId = env['AO_IT_ARENA'];
  final ownerEmail = env['AO_IT_OWNER_EMAIL'];
  final staffEmail = env['AO_IT_STAFF_EMAIL'];
  final outsiderEmail = env['AO_IT_OUTSIDER_EMAIL'];
  final handoff = env['AO_IT_HANDOFF'];
  final skip =
      [url, key, arenaId, ownerEmail, staffEmail, outsiderEmail].contains(null)
      ? 'local Supabase stack not configured (run tool/sync_it.sh)'
      : null;

  late SimDevice owner;
  late SimDevice staff;
  late SimDevice outsider;
  late String outsiderArena;
  late RealtimeSync staffLive;
  final ownerPushes = <List<String>>[];

  setUpAll(() async {
    if (skip != null) return;
    owner = await SimDevice.signIn('owner', url!, key!, ownerEmail!);
    staff = await SimDevice.signIn('staff', url, key, staffEmail!);
    outsider = await SimDevice.signIn('outsider', url, key, outsiderEmail!);
    owner.bind(arenaId!, onPushed: ownerPushes.add);
    // Wired like the app (cloud_root): the staff device announces each push the
    // server committed on the private channel, for the dashboard's live view.
    staffLive = RealtimeSync(
      client: staff.client,
      arenaId: arenaId,
      onSyncNeeded: () async {},
    );
    await staffLive.start();
    staff.bind(
      arenaId,
      onPushed: (kinds) => unawaited(staffLive.broadcastSync(kinds: kinds)),
    );
    // The outsider owns a different arena (self-serve sign-up path).
    outsiderArena = await outsider.client.rpc(
      'create_my_arena',
      params: {'p_arena_name': 'IT outsider', 'p_owner_name': 'Outsider'},
    ) as String;
    outsider.bind(outsiderArena);
    await owner.sync();
    await staff.sync();
  });

  tearDownAll(() async {
    if (skip != null) return;
    await staffLive.dispose();
    await owner.close();
    await staff.close();
    await outsider.close();
  });

  group('private arena channel', () {
    test('a member joins it; a login of another arena is refused', () async {
      expect(
        await _join(staff.client, arenaId!),
        RealtimeSubscribeStatus.subscribed,
      );
      expect(
        await _join(outsider.client, arenaId),
        isNot(RealtimeSubscribeStatus.subscribed),
        reason:
            'realtime.messages policies admit active members of the arena only',
      );
      expect(
        await _join(outsider.client, outsiderArena),
        RealtimeSubscribeStatus.subscribed,
        reason: 'its own arena works',
      );
    }, skip: skip);

    test('a committed push reaches the other device as a nudge with only the '
        'applied op kinds; the outsider hears nothing', () async {
      final heard = <Map<String, dynamic>>[];
      final overheard = <Map<String, dynamic>>[];
      final sender = RealtimeSync(
        client: owner.client,
        arenaId: arenaId!,
        onSyncNeeded: () async {},
      );
      await sender.start();
      // A separate session of another member (its own socket: one socket joins
      // a topic once). The owner's password is stable; the two-device suite
      // replaces the staff password on purpose.
      final listener = await SimDevice.signIn('listener', url!, key!, ownerEmail!);
      expect(
        await _join(listener.client, arenaId, broadcasts: heard),
        RealtimeSubscribeStatus.subscribed,
      );
      await _join(outsider.client, arenaId, broadcasts: overheard);
      await Future<void>.delayed(const Duration(seconds: 1));

      ownerPushes.clear();
      await owner.customers.createGuest();
      await owner.sync();
      expect(ownerPushes, [
        ['customer.create'],
      ], reason: 'the engine reports the kinds the server applied');
      await sender.broadcastSync(kinds: ownerPushes.single);

      await _until(() async => heard.isNotEmpty);
      final payload = RealtimeSync.nudgeOf(heard.single)!;
      expect(payload['arena_id'], arenaId);
      expect(payload['kinds'], ['customer.create']);
      expect(payload.keys.toSet(), {
        'arena_id',
        'kind',
        'kinds',
        'source',
        'at',
      }, reason: 'a nudge, never data');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(overheard, isEmpty, reason: 'another arena cannot listen in');
      await sender.dispose();
      await _leaveAll(outsider.client);
      await _leaveAll(listener.client);
      await listener.client.dispose();
    }, skip: skip);
  });

  group('arena isolation', () {
    test('another arena cannot read or write this one', () async {
      final t = SupabaseSyncTransport(outsider.client);
      await expectLater(
        t.pull(arenaId!, '0'),
        throwsA(isA<SyncAuthException>()),
        reason: 'sync_pull: active members only',
      );
      await expectLater(
        t.push(arenaId, [
          (
            opId: '00000000-0000-4000-8000-0000000000aa',
            kind: 'customer.create',
            payload: {
              'id': '00000000-0000-4000-8000-0000000000ab',
              'name': 'Intruder',
            },
          ),
        ], 'outsider'),
        throwsA(isA<SyncAuthException>()),
        reason: 'sync_push: active members only',
      );
      for (final table in [
        'sessions',
        'customers',
        'payments',
        'staff_profiles',
        'games',
      ]) {
        final rows = await outsider.client
            .from(table)
            .select('id')
            .eq('arena_id', arenaId);
        expect(rows, isEmpty, reason: 'RLS hides $table of another arena');
      }
    }, skip: skip);
  });

  group('dashboard → floor', () {
    final dashboard = handoff == null ? null : File('$handoff/dashboard.json');
    final noDashboard =
        skip ??
        ((dashboard?.existsSync() ?? false)
            ? null
            : 'dashboard phase 1 did not run (no \$AO_IT_HANDOFF/dashboard.json)');

    test(
      'the game and availability set on the dashboard reach the staff device; '
      'the staff run a session with it and hand it back',
      () async {
        final d =
            jsonDecode(dashboard!.readAsStringSync()) as Map<String, dynamic>;
        final gameId = d['game_id'] as String;
        final playableOn = d['playable_station_id'] as String;
        final notOn = d['other_station_id'] as String;
        await staff.sync();

        expect(
          (await staff.catalog.games()).map((g) => g.id),
          contains(gameId),
          reason: 'the dashboard game came down',
        );
        expect(
          await staff.catalog.availabilityOf(gameId, playableOn),
          GameAvailability.playable,
        );
        expect(
          await staff.catalog.availabilityOf(gameId, notOn),
          GameAvailability.notInstalled,
          reason: 'only where the owner marked it playable',
        );
        expect(
          (await staff.catalog.floorOptions()).warnMinutes,
          d['warn_minutes'],
          reason: 'the floor options the owner saved',
        );
        // The game the owner archived is kept for history but offered nowhere;
        // the one they deleted never reaches the device.
        final archived = d['archived_game_id'] as String;
        expect((await staff.catalog.gameById(archived))?.active, isFalse);
        expect(
          (await staff.catalog.gamesForResource(playableOn)).map((g) => g.game.id),
          isNot(contains(archived)),
          reason: 'an archived game is not offered for a new session',
        );
        expect(await staff.catalog.gameById(d['deleted_game_id'] as String), isNull);

        final guest = await staff.customers.createGuest();
        // Played yesterday 13:00–13:30 IST (07:30 UTC): inside opening hours
        // whatever time the suite runs, so the bill is real money (out of
        // hours, or ended in the same second, a session can bill nothing —
        // and a zero payment is refused).
        final today = DateTime.now().toUtc();
        final now = DateTime.utc(
          today.year,
          today.month,
          today.day,
          7,
          30,
        ).subtract(const Duration(days: 1));
        final snapshot = await staff.catalog.currentSnapshot();
        StartSessionCommand cmd(String station) => StartSessionCommand(
          customerId: guest.id,
          startedAt: now,
          scheduledEndAt: now.add(const Duration(hours: 1)),
          snapshot: snapshot,
          resourceId: station,
          resourceName: station,
          activityCode: d['activity_code'] as String,
          gameId: gameId,
          controllerCount: 1,
        );
        final refused = await staff.sessions.start(cmd(notOn));
        expect(refused.failureOrNull?.code, 'not_playable');
        final started = await staff.sessions.start(cmd(playableOn));
        expect(
          started.isOk,
          isTrue,
          reason: '${started.failureOrNull?.message}',
        );
        final id = started.valueOrNull!.id;

        final at = now.add(const Duration(minutes: 30));
        final s = (await staff.sessions.getById(id))!;
        final bill = const SegmentBilling().bill(
          snapshot: s.snapshot,
          segments: await staff.sessions.segmentsFor(id),
          openEndAt: at,
          sessionStart: s.startedAt,
        );
        expect(bill.total.value, greaterThan(0), reason: 'half an hour of play is billed');
        final ended = await staff.sessions.end(
          EndSessionCommand(
            sessionId: id,
            actualEndedAt: at,
            charges: bill.charges,
            billedAmountPaise: bill.total.value,
          ),
        );
        expect(ended.isOk, isTrue, reason: '${ended.failureOrNull?.message}');
        final paid = await staff.sessions.recordPayment(
          RecordPaymentCommand(
            sessionId: id,
            amountPaise: bill.total.value,
            method: PaymentMethod.upi,
          ),
        );
        expect(paid.isOk, isTrue, reason: '${paid.failureOrNull?.message}');
        final report = await staff.sync();
        expect(report.rejected, 0, reason: 'nothing refused');
        expect(await staff.outbox('pending'), isEmpty, reason: 'every op was sent and decided');
        // What the server holds (read through RLS as the staff member).
        final row = await staff.client
            .from('sessions')
            .select('status, actual_ended_at, billed_amount_paise')
            .eq('id', id)
            .single();
        expect(row['status'], isNot('active'), reason: 'the end applied on the server: $row');
        expect(row['billed_amount_paise'], bill.total.value);

        File('$handoff/floor.json').writeAsStringSync(
          jsonEncode({
            'session_id': id,
            'billed_paise': bill.total.value,
            'paid_paise': bill.total.value,
          }),
        );
      },
      skip: noDashboard,
    );

    test(
      'a game deleted after the staff device has it disappears from that '
      'device, with its station status, on the next pull',
      () async {
        final d =
            jsonDecode(dashboard!.readAsStringSync()) as Map<String, dynamic>;
        final station = d['playable_station_id'] as String;
        final gameId = const Uuid().v4();
        await owner.catalog.upsertGame(Game(
          id: gameId,
          name: 'IT Short-lived ${env['AO_IT_RUN']}',
          platforms: const ['PS5'],
          playerMode: PlayerMode.single,
          maxLocalPlayers: 1,
        ));
        await owner.catalog
            .setCompatibility(gameId, station, GameAvailability.playable);
        expect((await owner.sync()).rejected, 0);
        await staff.sync();
        expect(await staff.catalog.availabilityOf(gameId, station),
            GameAvailability.playable,
            reason: 'the staff device has the game before the delete');

        // The dashboard's delete: game.delete through sync_push, as the owner.
        final res = await owner.client.rpc('sync_push', params: {
          'p_arena': arenaId,
          'p_ops': [
            {
              'op_id': const Uuid().v4(),
              'kind': 'game.delete',
              'payload': {'id': gameId},
            },
          ],
          'p_device': 'it',
        }) as Map<String, dynamic>;
        expect((res['results'] as List).single['status'], 'applied');

        await staff.sync();
        expect(await staff.catalog.gameById(gameId), isNull);
        expect(
          (await staff.catalog.compatibility()).where((c) => c.gameId == gameId),
          isEmpty,
          reason: 'its station status went with it',
        );
      },
      skip: noDashboard,
    );
  });
}
