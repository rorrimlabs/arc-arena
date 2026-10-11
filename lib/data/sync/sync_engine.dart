/// Moves the outbox to the server and the server's changes onto the device.
///
/// One pass ([syncNow]):
///  1. PUSH every pending op, oldest first. The server applies each once
///     (a retried op replays its first answer), so a timeout or a crash between
///     sending and recording the answer can never apply an op twice.
///  2. ROLL BACK what the server refused: the device's copy of each affected
///     entity (session, group, pad, customer, booking — or the whole catalog)
///     is replaced with the server's. The refused op itself is kept, with the
///     server's reason, until someone acknowledges it.
///  3. PULL everything committed since the cursor and apply it.
///
/// Steps 2–3 only run when the outbox is empty, and their writes happen in a
/// Drift transaction that re-checks that — so server rows are never laid over a
/// local change the server has not seen yet. A change made mid-pass simply
/// triggers another pass.
///
/// What this does NOT promise: an offline device cannot know what another
/// device did meanwhile. Conflicting work done offline (the same station, the
/// same pad, the same booking, a bill priced from a stale session) is refused
/// by the server on reconnect and surfaced as "needs attention" — never merged
/// silently.
library;

import 'dart:async';
import 'dart:convert';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/sync/sync_applier.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

enum SyncState {
  /// Cloud sync is not set up on this device (local-only mode).
  localOnly,

  /// Everything this device did is on the server, and the last pull worked.
  synced,

  /// Changes are saved on this device and waiting to be sent.
  pending,

  /// A pass is running.
  syncing,

  /// The server could not be reached; changes stay on this device until it can.
  offline,

  /// The sign-in expired or access was turned off; nothing syncs until fixed.
  authProblem,

  /// The server answered with an unexpected error; retried with backoff.
  error,
}

@immutable
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.pending = 0,
    this.needsAttention = 0,
    this.lastSyncedAt,
    this.message,
    this.accessRevoked = false,
  });

  static const localOnly = SyncStatus(state: SyncState.localOnly);

  final SyncState state;

  /// Ops saved on this device, not yet accepted or refused by the server.
  final int pending;

  /// Ops the server refused that nobody has acknowledged yet.
  final int needsAttention;
  final DateTime? lastSyncedAt;
  final String? message;
  final bool accessRevoked;

  SyncStatus copyWith({
    SyncState? state,
    int? pending,
    int? needsAttention,
    DateTime? lastSyncedAt,
    String? message,
    bool? accessRevoked,
  }) =>
      SyncStatus(
        state: state ?? this.state,
        pending: pending ?? this.pending,
        needsAttention: needsAttention ?? this.needsAttention,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        message: message,
        accessRevoked: accessRevoked ?? this.accessRevoked,
      );

  @override
  String toString() =>
      'SyncStatus($state, pending: $pending, attention: $needsAttention, $message)';
}

/// What one pass did (for tests and logs).
class SyncReport {
  int applied = 0;
  int rejected = 0;
  int rolledBack = 0;
  int pulledChanges = 0;
  SyncState endedIn = SyncState.synced;

  @override
  String toString() => 'SyncReport(applied: $applied, rejected: $rejected, '
      'rolledBack: $rolledBack, pulled: $pulledChanges, $endedIn)';
}

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.transport,
    required this.arenaId,
    this.clock = const SystemClock(),
    this.pollEvery = const Duration(seconds: 10),
    this.batchSize = 50,
  }) : _applier = SyncApplier(db);

  final AppDatabase db;
  final SyncTransport transport;
  final String arenaId;
  final Clock clock;
  final Duration pollEvery;
  final int batchSize;
  final SyncApplier _applier;

  static const _uuid = Uuid();
  static const cursorKey = 'pull_cursor';
  static const deviceKey = 'device_id';
  static const lastSyncKey = 'last_synced_at';
  static const clockOffsetKey = 'clock_offset_ms';

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(state: SyncState.pending);
  Future<SyncReport>? _running;
  bool _again = false;
  Timer? _poll;
  Timer? _debounce;
  int _failures = 0;
  DateTime? _notBefore;
  bool _stopped = false;

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _status;

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Starts background passes: now, after every local change ([nudge]), and
  /// every [pollEvery] (that is how other devices' changes arrive).
  void start() {
    _stopped = false;
    unawaited(syncNow());
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) {
      final wait = _notBefore;
      if (wait != null && clock.now().isBefore(wait)) return;
      unawaited(syncNow());
    });
  }

  void stop() {
    _stopped = true;
    _poll?.cancel();
    _debounce?.cancel();
  }

  Future<void> dispose() async {
    stop();
    await _running;
    await _statusController.close();
  }

  /// A local change was recorded: sync soon (coalescing bursts of writes).
  void nudge() {
    if (_stopped) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // A nudge is fresh work, so it does not wait out an offline backoff.
      _notBefore = null;
      unawaited(syncNow());
    });
  }

  /// One full pass. Concurrent calls share the running pass and schedule one
  /// more, so no change is missed and no two passes overlap.
  Future<SyncReport> syncNow() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final pass = _pass();
    _running = pass;
    return pass.whenComplete(() {
      _running = null;
      if (_again && !_stopped) {
        _again = false;
        unawaited(syncNow());
      }
    });
  }

  /// This device's id (sent with every push; created once).
  Future<String> deviceId() async {
    final row = await (db.select(db.syncMeta)..where((t) => t.key.equals(deviceKey)))
        .getSingleOrNull();
    if (row != null) return row.value;
    final id = _uuid.v4();
    await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaRow(key: deviceKey, value: id));
    return id;
  }

  Future<int> _count(String status, {bool unresolvedOnly = false}) async {
    final q = db.selectOnly(db.syncOutbox)
      ..addColumns([db.syncOutbox.seq.count()])
      ..where(db.syncOutbox.status.equals(status));
    if (unresolvedOnly) q.where(db.syncOutbox.resolvedAt.isNull());
    return (await q.getSingle()).read(db.syncOutbox.seq.count()) ?? 0;
  }

  Future<SyncStatus> _counts(SyncStatus base) async => base.copyWith(
        state: base.state,
        message: base.message,
        pending: await _count(OutboxStatus.pending),
        needsAttention:
            await _count(OutboxStatus.rejected, unresolvedOnly: true),
      );

  Future<SyncReport> _pass() async {
    final report = SyncReport();
    _emit(await _counts(_status.copyWith(state: SyncState.syncing)));
    try {
      await _push(report);
      if (await _count(OutboxStatus.pending) == 0) {
        await _reconcile(report);
      }
      _failures = 0;
      _notBefore = null;
      final pending = await _count(OutboxStatus.pending);
      report.endedIn = pending == 0 ? SyncState.synced : SyncState.pending;
      final now = clock.now();
      if (pending == 0) await _setMeta(lastSyncKey, now.toIso8601String());
      _emit(await _counts(SyncStatus(
        state: report.endedIn,
        lastSyncedAt: pending == 0 ? now : _status.lastSyncedAt,
      )));
    } on SyncOfflineException catch (e) {
      report.endedIn = SyncState.offline;
      _backoff();
      _emit(await _counts(_status.copyWith(
          state: SyncState.offline, message: 'Server unreachable ($e)')));
    } on SyncAuthException catch (e) {
      report.endedIn = SyncState.authProblem;
      stop();
      _emit(await _counts(_status.copyWith(
        state: SyncState.authProblem,
        accessRevoked: e.revoked,
        message: e.revoked
            ? 'Your access to this arena was turned off.'
            : 'Sign in again to keep syncing.',
      )));
    } on Object catch (e) {
      report.endedIn = SyncState.error;
      _backoff();
      _emit(await _counts(
          _status.copyWith(state: SyncState.error, message: 'Sync failed: $e')));
    }
    return report;
  }

  void _backoff() {
    _failures++;
    final seconds = [2, 4, 8, 16, 32, 60][(_failures - 1).clamp(0, 5)];
    _notBefore = clock.now().add(Duration(seconds: seconds));
  }

  // ----------------------------------------------------------------- push

  Future<void> _push(SyncReport report) async {
    final device = await deviceId();
    while (true) {
      final batch = await (db.select(db.syncOutbox)
            ..where((t) => t.status.equals(OutboxStatus.pending))
            ..orderBy([(t) => OrderingTerm(expression: t.seq)])
            ..limit(batchSize))
          .get();
      if (batch.isEmpty) return;

      final attemptAt = clock.now();
      await db.transaction(() async {
        for (final o in batch) {
          await (db.update(db.syncOutbox)..where((t) => t.seq.equals(o.seq)))
              .write(SyncOutboxCompanion(
            attempts: Value(o.attempts + 1),
            lastAttemptAt: Value(attemptAt),
          ));
        }
      });

      final results = await transport.push(arenaId, [
        for (final o in batch)
          (
            opId: o.opId,
            kind: o.kind,
            payload: jsonDecode(o.payload) as Map<String, dynamic>,
          ),
      ], device);
      final byId = {for (final r in results) r.opId: r};

      var stop = false;
      await db.transaction(() async {
        final now = clock.now();
        for (final o in batch) {
          final r = byId[o.opId];
          if (r == null || r.status == 'retry') {
            // Not decided (a transient lock on the server). Keep order: stop.
            stop = true;
            break;
          }
          if (r.status == 'applied') {
            report.applied++;
            await (db.update(db.syncOutbox)..where((t) => t.seq.equals(o.seq)))
                .write(SyncOutboxCompanion(
              status: const Value(OutboxStatus.applied),
              result: Value(r.result == null ? null : jsonEncode(r.result)),
              needsRefetch: Value(r.adjusted),
              resolvedAt: Value(now),
            ));
          } else {
            report.rejected++;
            await (db.update(db.syncOutbox)..where((t) => t.seq.equals(o.seq)))
                .write(SyncOutboxCompanion(
              status: const Value(OutboxStatus.rejected),
              errorCode: Value(r.error),
              errorDetail: Value(r.detail),
              needsRefetch: const Value(true),
            ));
          }
        }
      });
      if (stop) return;
    }
  }

  // ------------------------------------------------- roll back + pull

  /// The entities an op wrote on this device (its own + every pad it moved or
  /// allocated), in rollback order: parents first, pads last.
  static List<({String type, String id})> refsFor(SyncOutboxRow op) {
    final refs = <({String type, String id})>[
      (type: op.entityType, id: op.entityId),
    ];
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final pads = <String>{};
    void collect(Object? list) {
      if (list is! List) return;
      for (final e in list) {
        final id = (e as Map)['controller_id'];
        if (id is String) pads.add(id);
      }
    }

    collect(payload['allocations']);
    collect(payload['moves']);
    for (final a in [
      ...?(payload['assignments'] as List?),
      if (payload['assignment'] != null) payload['assignment'],
    ]) {
      collect((a as Map)['allocations']);
      collect(a['moves']);
    }
    if (op.kind == 'controller.move' || op.kind.startsWith('controller.')) {
      final id = payload['controller_id'] ?? payload['id'];
      if (id is String) pads.add(id);
    }
    for (final id in pads) {
      if (!(op.entityType == 'controller' && op.entityId == id)) {
        refs.add((type: 'controller', id: id));
      }
    }
    return refs;
  }

  Future<void> _reconcile(SyncReport report) async {
    final toRefetch = await (db.select(db.syncOutbox)
          ..where((t) => t.needsRefetch.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
        .get();

    final entityRefs = <({String type, String id})>[];
    var catalog = false;
    for (final op in toRefetch) {
      if (op.entityType == 'catalog' || op.entityType == 'staff') {
        catalog = true;
        continue;
      }
      for (final r in refsFor(op)) {
        if (!entityRefs.contains(r)) entityRefs.add(r);
      }
    }
    // Parents before pads, so a pad's open allocation from a refused session is
    // already gone when the pad's own rows are applied.
    entityRefs.sort((a, b) =>
        (a.type == 'controller' ? 1 : 0).compareTo(b.type == 'controller' ? 1 : 0));

    final fetched = entityRefs.isEmpty
        ? const <EntityRows>[]
        : await transport.fetchEntities(arenaId, entityRefs);
    List<ServerRow>? catalogRows;
    if (catalog) {
      catalogRows = [];
      var c = '0';
      while (true) {
        final page = await transport.pull(arenaId, c, limit: 100000);
        for (final ch in page.changes) {
          final t = ch['t'] as String;
          if (catalogTables.contains(t)) {
            catalogRows.add((table: t, row: Map<String, dynamic>.from(ch['r'] as Map)));
          }
        }
        c = page.cursor;
        if (!page.hasMore) break;
      }
    }

    var cursor = await _meta(cursorKey) ?? '0';
    var first = true;
    while (true) {
      final page = await transport.pull(arenaId, cursor);
      final applied = await db.transaction(() async {
        // A local write slipped in since the push: its op has not reached the
        // server, so the server's rows must not be laid over it yet.
        if (await _count(OutboxStatus.pending) > 0) return false;
        if (first) {
          for (final e in fetched) {
            await _applier.replaceEntity(e.type, e.id, [
              for (final r in e.rows)
                (table: r['t'] as String, row: Map<String, dynamic>.from(r['r'] as Map)),
            ]);
          }
          if (catalogRows != null) await _applier.replaceCatalog(catalogRows);
          if (toRefetch.isNotEmpty) {
            await (db.update(db.syncOutbox)
                  ..where((t) => t.seq.isIn([for (final o in toRefetch) o.seq])))
                .write(const SyncOutboxCompanion(needsRefetch: Value(false)));
            report.rolledBack += toRefetch.length;
          }
        }
        await _applier.applyChanges(page.changes);
        await _setMeta(cursorKey, page.cursor);
        final serverTime = page.serverTime;
        if (serverTime != null) {
          await _setMeta(clockOffsetKey,
              '${serverTime.difference(clock.now()).inMilliseconds}');
        }
        return true;
      });
      if (!applied) return;
      first = false;
      report.pulledChanges += page.changes.length;
      cursor = page.cursor;
      if (!page.hasMore) return;
    }
  }

  Future<String?> _meta(String key) async =>
      (await (db.select(db.syncMeta)..where((t) => t.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> _setMeta(String key, String value) => db
      .into(db.syncMeta)
      .insertOnConflictUpdate(SyncMetaRow(key: key, value: value));

  /// Marks a refused op as seen by a person (it stays in the outbox as history).
  Future<void> acknowledge(String opId) async {
    await (db.update(db.syncOutbox)..where((t) => t.opId.equals(opId)))
        .write(SyncOutboxCompanion(resolvedAt: Value(clock.now())));
    _emit(await _counts(_status));
  }
}
