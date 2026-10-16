/// Records operations for cloud sync into the Drift outbox.
///
/// Repositories call [record] INSIDE the transaction that makes the local
/// change, so the change and the op describing it commit or roll back together
/// — there is never a local change the server will not hear about, nor an op
/// for a change that did not happen. In local-only mode no recorder exists and
/// nothing is enqueued.
///
/// An op carries every row id the device generated (session, segment, pad
/// allocations, moves, charges, payment …) so the server writes the same ids
/// and the two copies share identity.
library;

import 'dart:convert';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class SyncRecorder {
  SyncRecorder(
    this._db, {
    required this.actor,
    this.clock = const SystemClock(),
    this.onRecorded,
  });

  final AppDatabase _db;

  /// Who is signed in on this device (recorded with each op).
  final String? Function() actor;
  final Clock clock;

  /// Nudges the sync engine. Fired after the insert; the engine's own read
  /// waits for the surrounding transaction, so it never sees a rolled-back op.
  final void Function()? onRecorded;
  static const _uuid = Uuid();

  /// Appends one op. Call inside the caller's transaction.
  Future<String> record({
    required String kind,
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
  }) async {
    final opId = _uuid.v4();
    await _db.into(_db.syncOutbox).insert(SyncOutboxCompanion.insert(
          opId: opId,
          kind: kind,
          entityType: entityType,
          entityId: entityId,
          payload: jsonEncode(payload),
          status: OutboxStatus.pending,
          actorId: Value(actor()),
          createdAt: clock.now(),
        ));
    onRecorded?.call();
    return opId;
  }

  /// The server version last seen for an editable row (customers, bookings),
  /// or null when the row was created on this device and never pulled.
  Future<String?> baseVersion(String entity, String rowId) async {
    final row = await (_db.select(_db.syncVersions)
          ..where((t) => t.entity.equals(entity) & t.rowId.equals(rowId)))
        .getSingleOrNull();
    return row?.version;
  }
}

/// Outbox status codes.
abstract final class OutboxStatus {
  static const pending = 'pending';
  static const applied = 'applied';
  static const rejected = 'rejected';
}

/// Wire helpers shared by every op payload.
abstract final class Wire {
  /// Instants travel as ISO-8601 UTC with microseconds — exactly what Drift
  /// stores (text mode), so the server's stale checks compare equal values.
  static String? at(DateTime? t) => t?.toUtc().toIso8601String();

  static List<Map<String, Object?>> pads(List<ControllerAllocationRow> rows) => [
        for (final r in rows) {'id': r.id, 'controller_id': r.controllerId},
      ];

  static List<Map<String, Object?>> moves(List<ControllerMoveRow> rows) => [
        for (final r in rows) {'id': r.id, 'controller_id': r.controllerId},
      ];
}
