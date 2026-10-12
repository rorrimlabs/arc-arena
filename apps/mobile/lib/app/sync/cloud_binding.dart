/// What cloud mode binds this app run to: one arena, one signed-in person, one
/// device database file, one sync engine. Absent (null) in local-only mode, in
/// which case every provider below falls back to today's behaviour.
library;

import 'dart:async';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloudBinding {
  CloudBinding({
    required this.arenaId,
    required this.arenaName,
    required this.userId,
    required this.email,
    required this.engine,
    required this.recorder,
    required this.clock,
    required this.signOut,
    required this.addStaffByEmail,
    required this.changePassword,
  });

  final String arenaId;
  final String arenaName;
  final String userId;
  final String email;
  final SyncEngine engine;
  final SyncRecorder recorder;

  /// Device time corrected by the server offset once it is significant.
  final OffsetClock clock;

  /// Ends the cloud session on this device and returns to the sign-in gate.
  final Future<void> Function() signOut;

  /// Owner-only, online-only: give an EXISTING login access to this arena with
  /// the chosen permissions. It does not create the login — the owner creates
  /// that in the Supabase dashboard (migration 0015).
  final Future<void> Function(String email, String name, List<String> perms)
      addStaffByEmail;

  /// Online-only: replace the signed-in person's own password, so a login the
  /// owner set up becomes credentials only that person knows.
  final Future<void> Function(String newPassword) changePassword;
}

/// Overridden in cloud mode; null in local-only mode.
final cloudBindingProvider = Provider<CloudBinding?>((ref) => null);

/// The outbox recorder the repositories write through (null = local-only).
final syncRecorderProvider =
    Provider<SyncRecorder?>((ref) => ref.watch(cloudBindingProvider)?.recorder);

/// Live sync status for the status strip and the Sync screen.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final binding = ref.watch(cloudBindingProvider);
  if (binding == null) return Stream.value(SyncStatus.localOnly);
  final engine = binding.engine;
  final controller = StreamController<SyncStatus>();
  controller.add(engine.status);
  final sub = engine.statusStream.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Counts sync passes that brought server changes onto this device (0 in
/// local-only mode). One-shot catalog providers watch it so a station, game or
/// price another device changed shows up without a restart.
final syncRevisionProvider = StreamProvider<int>((ref) async* {
  final binding = ref.watch(cloudBindingProvider);
  yield 0;
  if (binding == null) return;
  var n = 0;
  yield* binding.engine.dataChanged.map((_) => ++n);
});
