/// Dashboard → floor, LIVE: a staff device joined to the private arena channel
/// (the app's real RealtimeSync) is nudged by the owner's dashboard change
/// without polling, and the pull that follows brings the change.
///
/// Run by `bash tool/sync_it.sh`, which starts this file in the background,
/// waits for $AO_IT_HANDOFF/flutter_listening (written once the channel is
/// joined), then runs the dashboard phase 1. Skipped without that environment.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arena_ops/data/sync/realtime_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sim_device.dart';

void main() {
  final env = Platform.environment;
  final url = env['AO_SUPABASE_URL'];
  final key = env['AO_SUPABASE_ANON_KEY'];
  final arenaId = env['AO_IT_ARENA'];
  final staffEmail = env['AO_IT_STAFF_EMAIL'];
  final handoff = env['AO_IT_HANDOFF'];
  final skip = ([url, key, arenaId, staffEmail, handoff].contains(null) ||
          env['AO_IT_LISTEN'] != '1')
      ? 'run by tool/sync_it.sh (live listener phase)'
      : null;

  test('a dashboard change reaches the staff device live over the private channel',
      () async {
    final staff = await SimDevice.signIn('staff-live', url!, key!, staffEmail!);
    staff.bind(arenaId!);
    await staff.sync(); // baseline: everything before the dashboard phase
    final nudged = Completer<void>();
    final rt = RealtimeSync(
      client: staff.client,
      arenaId: arenaId,
      onSyncNeeded: () async {
        if (!nudged.isCompleted) nudged.complete();
      },
      onSubscribed: () => File('$handoff/flutter_listening').writeAsStringSync('joined'),
    );
    await rt.start();
    await nudged.future.timeout(const Duration(seconds: 150),
        onTimeout: () => fail('no Realtime nudge from the dashboard (channel refused or '
            'event not delivered); see the realtime.messages policies'));

    // The nudge is only a signal; the authoritative pull brings the data.
    final dashboard = File('$handoff/dashboard.json');
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (!dashboard.existsSync() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final gameId = (jsonDecode(dashboard.readAsStringSync()) as Map)['game_id'] as String;
    var seen = false;
    while (!seen && DateTime.now().isBefore(end)) {
      await staff.sync();
      seen = (await staff.catalog.games()).any((g) => g.id == gameId);
      if (!seen) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(seen, isTrue, reason: 'the pull after the nudge brought the dashboard game');
    await rt.dispose();
    await staff.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
