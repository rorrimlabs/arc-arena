import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/local/controller_allocator.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/mappers.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/repositories/group_session_repository.dart';
import 'package:arena_ops/domain/services/payment_rules.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Local (Drift) implementation of [GroupSessionRepository]. Mirrors
/// [LocalSessionRepository]: every mutation runs in a transaction and re-checks
/// conflicts across BOTH single-session segments and group assignments, so the
/// one authoritative time window and the no-double-occupancy rule hold even with
/// concurrent writers (group feature §5–§9).
class LocalGroupSessionRepository implements GroupSessionRepository {
  LocalGroupSessionRepository(this._db,
      [this._clock = const SystemClock(), this._sync]);

  final AppDatabase _db;
  final Clock _clock;

  /// Cloud mode only: records each change as a sync op in the same
  /// transaction. Null in local-only mode.
  final SyncRecorder? _sync;

  /// One assignment as the server's group ops expect it.
  static Map<String, Object?> _assignmentWire(
    GroupAssignmentRow a,
    List<ControllerAllocationRow> pads,
    List<ControllerMoveRow> moves,
  ) =>
      {
        'id': a.id,
        'player_number': a.playerNumber,
        'player_label': a.playerLabel,
        'idx': a.index,
        'resource_id': a.resourceId,
        'activity_code': a.activityCode,
        'game_id': a.gameId,
        'controller_count': a.controllerCount,
        'allocations': Wire.pads(pads),
        'moves': Wire.moves(moves),
      };
  static const _uuid = Uuid();

  /// Controller ports a PS5 can fill at once — a hardware ceiling, distinct
  /// from how many working pads are actually on the station.
  static const int portCapacity = 4;

  ControllerAllocator get _alloc => ControllerAllocator(_db, _uuid);

  // --- reads -----------------------------------------------------------------

  SimpleSelectStatement<$GroupSessionsTable, GroupSessionRow> _activeQuery() =>
      _db.select(_db.groupSessions)
        ..where((t) => t.status.equals(GroupSessionStatus.active.code))
        ..orderBy([(t) => OrderingTerm(expression: t.scheduledEndAt)]);

  Future<ActiveGroupSession> _withAssignments(GroupSessionRow r) async =>
      ActiveGroupSession(
        group: groupSessionFromRow(r),
        assignments: await assignmentsFor(r.id),
      );

  @override
  Stream<List<ActiveGroupSession>> watchActiveGroups() =>
      _activeQuery().watch().asyncMap(
          (rows) async => [for (final r in rows) await _withAssignments(r)]);

  @override
  Future<List<ActiveGroupSession>> activeGroups() async =>
      [for (final r in await _activeQuery().get()) await _withAssignments(r)];

  SimpleSelectStatement<$GroupAssignmentsTable, GroupAssignmentRow>
      _openQuery() =>
          _db.select(_db.groupAssignments)..where((t) => t.endedAt.isNull());

  @override
  Stream<List<GroupAssignment>> watchOpenAssignments() =>
      _openQuery().watch().map((r) => r.map(groupAssignmentFromRow).toList());

  @override
  Future<List<GroupAssignment>> openAssignments() async =>
      (await _openQuery().get()).map(groupAssignmentFromRow).toList();

  @override
  Future<GroupSession?> getById(String id) async {
    final row =
        await (_db.select(_db.groupSessions)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : groupSessionFromRow(row);
  }

  @override
  Stream<GroupSession?> watchById(String id) =>
      (_db.select(_db.groupSessions)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : groupSessionFromRow(r));

  @override
  Future<List<GroupAssignment>> assignmentsFor(String groupId) async {
    final rows = await (_db.select(_db.groupAssignments)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.playerNumber),
            (t) => OrderingTerm(expression: t.index),
          ]))
        .get();
    return rows.map(groupAssignmentFromRow).toList();
  }

  @override
  Future<List<GroupSession>> recent({int limit = 30}) async {
    final rows = await (_db.select(_db.groupSessions)
          ..where((t) => t.status.equals(GroupSessionStatus.active.code).not())
          ..orderBy([
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .get();
    return rows.map(groupSessionFromRow).toList();
  }

  @override
  Future<List<GroupSession>> inRange(DateTime fromUtc, DateTime toUtc) async {
    final rows = await (_db.select(_db.groupSessions)
          ..where((t) =>
              t.startedAt.isBiggerOrEqualValue(fromUtc) &
              t.startedAt.isSmallerThanValue(toUtc)))
        .get();
    return rows.map(groupSessionFromRow).toList();
  }

  @override
  Future<List<GroupAssignment>> assignmentsInRange(
      DateTime fromUtc, DateTime toUtc) async {
    final rows = await (_db.select(_db.groupAssignments)
          ..where((t) =>
              t.startedAt.isSmallerThanValue(toUtc) &
              (t.endedAt.isNull() | t.endedAt.isBiggerThanValue(fromUtc))))
        .get();
    return rows.map(groupAssignmentFromRow).toList();
  }

  @override
  Future<List<GroupCharge>> chargesInRange(
      DateTime fromUtc, DateTime toUtc) async {
    final rows = await (_db.select(_db.groupCharges)
          ..where((t) =>
              t.segmentStart.isSmallerThanValue(toUtc) &
              t.segmentEnd.isBiggerThanValue(fromUtc)))
        .get();
    return rows.map(groupChargeFromRow).toList();
  }

  @override
  Future<List<GroupPayment>> paymentsInRange(
      DateTime fromUtc, DateTime toUtc) async {
    final rows = await (_db.select(_db.groupPayments)
          ..where((t) =>
              t.createdAt.isBiggerOrEqualValue(fromUtc) &
              t.createdAt.isSmallerThanValue(toUtc)))
        .get();
    return rows.map(groupPaymentFromRow).toList();
  }

  // --- critical operations ---------------------------------------------------

  @override
  Future<Result<GroupSession>> create(CreateGroupCommand cmd) async {
    if (cmd.assignments.isEmpty) {
      return const Err(Failure(
        message: 'Assign at least one player to a system.',
        code: 'no_assignments',
      ));
    }
    try {
      final row = await _db.transaction(() async {
        final now = _clock.now();
        final group = GroupSessionRow(
          id: _uuid.v4(),
          primaryCustomerId: cmd.primaryCustomerId,
          playerCount: cmd.playerCount,
          purchasedControllerCount: cmd.purchasedControllerCount,
          status: GroupSessionStatus.active.code,
          paymentStatus: PaymentStatus.unpaid.code,
          startedAt: cmd.startedAt.toUtc(),
          scheduledEndAt: cmd.scheduledEndAt.toUtc(),
          actualEndedAt: null,
          pricingSnapshot: cmd.snapshot.toJson(),
          billingMode: cmd.billingMode.code,
          billedAmountPaise: null,
          voidReason: null,
          createdAt: now,
          updatedAt: now,
        );
        await _db.into(_db.groupSessions).insert(group);

        // Track the next index per player as we insert.
        final nextIndex = <int, int>{};
        final wire = <Map<String, Object?>>[];
        for (final d in cmd.assignments) {
          await _ensureAssignable(
            groupId: group.id,
            resourceId: d.resourceId,
            resourceName: d.resourceName,
            activityCode: d.activityCode,
            gameId: d.gameId,
            controllerCount: d.controllerIds?.length ?? d.controllerCount ?? 0,
            playerNumber: d.playerNumber,
            borrowed: d.borrowControllerIds?.length ?? 0,
          );
          final index = nextIndex[d.playerNumber] ?? 0;
          nextIndex[d.playerNumber] = index + 1;
          final assignment = await _insertAssignment(
            groupId: group.id,
            playerNumber: d.playerNumber,
            playerLabel: d.playerLabel,
            index: index,
            resourceId: d.resourceId,
            activityCode: d.activityCode,
            gameId: d.gameId,
            controllerCount: d.controllerIds?.length ?? d.controllerCount,
            startedAt: cmd.startedAt.toUtc(),
            now: now,
          );
          var moves = const <ControllerMoveRow>[];
          if (d.borrowControllerIds != null &&
              d.borrowControllerIds!.isNotEmpty) {
            moves = await _alloc.borrow(
              controllerIds: d.borrowControllerIds!,
              resourceId: d.resourceId,
              resourceName: d.resourceName,
              sessionRef: Controller.groupRef(group.id),
              at: cmd.startedAt.toUtc(),
              now: now,
            );
          }
          var pads = const <ControllerAllocationRow>[];
          if (d.controllerIds != null && d.controllerIds!.isNotEmpty) {
            pads = await _alloc.allocate(
              scope: 'group',
              groupId: group.id,
              assignmentId: assignment.id,
              playerNumber: d.playerNumber,
              playerLabel: d.playerLabel,
              controllerIds: d.controllerIds!,
              resourceId: d.resourceId,
              resourceName: d.resourceName,
              activityCode: d.activityCode,
              gameId: d.gameId,
              startedAt: cmd.startedAt.toUtc(),
              now: now,
              requestId: cmd.requestId,
            );
          }
          wire.add(_assignmentWire(assignment, pads, moves));
          await _touchGame(d.gameId, cmd.startedAt.toUtc());
        }
        await (_db.update(_db.customers)
              ..where((t) => t.id.equals(cmd.primaryCustomerId)))
            .write(CustomersCompanion(lastVisitAt: Value(cmd.startedAt.toUtc())));
        await _sync?.record(
          kind: 'group.create',
          entityType: 'group',
          entityId: group.id,
          payload: {
            'id': group.id,
            'primary_customer_id': group.primaryCustomerId,
            'player_count': group.playerCount,
            'purchased_controller_count': group.purchasedControllerCount,
            'started_at': Wire.at(group.startedAt),
            'scheduled_end_at': Wire.at(group.scheduledEndAt),
            'pricing_snapshot': group.pricingSnapshot,
            'billing_mode': group.billingMode,
            'assignments': wire,
          },
        );
        return group;
      });
      return Ok(groupSessionFromRow(row));
    } on ControllerAllocationException catch (e) {
      return Err(e.failure);
    } on _AssignBlocked catch (e) {
      return Err(e.failure);
    } catch (_) {
      return const Err(Failure(
        message: 'Could not start the group session.',
        fix: 'Check the system assignments and try again.',
        code: 'group_create_failed',
      ));
    }
  }

  @override
  Future<Result<GroupAssignment>> addAssignment(AddAssignmentCommand cmd) async {
    final group = await getById(cmd.groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    if (!group.isActive) {
      return const Err(Failure(
        message: 'This group session is not active.',
        code: 'not_active',
      ));
    }
    final existing = await assignmentsFor(cmd.groupId);
    if (existing.any((a) => a.playerNumber == cmd.playerNumber && a.isOpen)) {
      return const Err(Failure(
        message: 'That player is already on a system.',
        fix: 'Use Switch system instead.',
        code: 'player_busy',
      ));
    }
    try {
      final seg = await _db.transaction(() async {
        final now = _clock.now();
        final at = cmd.at.toUtc();
        await _ensureAssignable(
          groupId: cmd.groupId,
          resourceId: cmd.resourceId,
          resourceName: cmd.resourceName,
          activityCode: cmd.activityCode,
          gameId: cmd.gameId,
          controllerCount: cmd.controllerIds?.length ?? cmd.controllerCount ?? 0,
          playerNumber: cmd.playerNumber,
          borrowed: cmd.borrowControllerIds?.length ?? 0,
        );
        final index = existing
                .where((a) => a.playerNumber == cmd.playerNumber)
                .fold<int>(-1, (m, a) => a.index > m ? a.index : m) +
            1;
        final row = await _insertAssignment(
          groupId: cmd.groupId,
          playerNumber: cmd.playerNumber,
          playerLabel: cmd.playerLabel,
          index: index,
          resourceId: cmd.resourceId,
          activityCode: cmd.activityCode,
          gameId: cmd.gameId,
          controllerCount: cmd.controllerIds?.length ?? cmd.controllerCount,
          startedAt: at,
          now: now,
        );
        var moves = const <ControllerMoveRow>[];
        if (cmd.borrowControllerIds != null &&
            cmd.borrowControllerIds!.isNotEmpty) {
          moves = await _alloc.borrow(
            controllerIds: cmd.borrowControllerIds!,
            resourceId: cmd.resourceId,
            resourceName: cmd.resourceName,
            sessionRef: Controller.groupRef(cmd.groupId),
            at: at,
            now: now,
          );
        }
        var pads = const <ControllerAllocationRow>[];
        if (cmd.controllerIds != null && cmd.controllerIds!.isNotEmpty) {
          pads = await _alloc.allocate(
            scope: 'group',
            groupId: cmd.groupId,
            assignmentId: row.id,
            playerNumber: cmd.playerNumber,
            playerLabel: cmd.playerLabel,
            controllerIds: cmd.controllerIds!,
            resourceId: cmd.resourceId,
            resourceName: cmd.resourceName,
            activityCode: cmd.activityCode,
            gameId: cmd.gameId,
            startedAt: at,
            now: now,
          );
        }
        await _touchGroup(cmd.groupId, now);
        await _touchGame(cmd.gameId, at);
        await _sync?.record(
          kind: 'group.add',
          entityType: 'group',
          entityId: cmd.groupId,
          payload: {
            'group_id': cmd.groupId,
            'at': Wire.at(at),
            'assignment': _assignmentWire(row, pads, moves),
          },
        );
        return row;
      });
      return Ok(groupAssignmentFromRow(seg));
    } on ControllerAllocationException catch (e) {
      return Err(e.failure);
    } on _AssignBlocked catch (e) {
      return Err(e.failure);
    } catch (_) {
      return const Err(Failure(
        message: 'Could not assign that system.',
        code: 'assign_failed',
      ));
    }
  }

  @override
  Future<Result<GroupAssignment>> switchAssignment(
      SwitchAssignmentCommand cmd) async {
    final group = await getById(cmd.groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    if (!group.isActive) {
      return const Err(Failure(
        message: 'This group session is not active.',
        fix: 'Only active groups can be changed.',
        code: 'not_active',
      ));
    }
    final assignments = await assignmentsFor(cmd.groupId);
    GroupAssignment? open;
    for (final a in assignments) {
      if (a.playerNumber == cmd.playerNumber && a.isOpen) {
        open = a;
        break;
      }
    }
    if (open == null) {
      return const Err(Failure(
        message: 'That player has no active system.',
        fix: 'Add the player to a system first.',
        code: 'no_open_assignment',
      ));
    }
    final current = open;
    final at = cmd.at.toUtc();
    if (at.isBefore(current.startedAt)) {
      return const Err(Failure(
        message: 'Change time is before the assignment started.',
        code: 'invalid_time',
      ));
    }

    try {
      final newSeg = await _db.transaction(() async {
        final now = _clock.now();
        // Re-check across both worlds, ignoring this player's own current spot.
        await _ensureAssignable(
          groupId: cmd.groupId,
          resourceId: cmd.resourceId,
          resourceName: cmd.resourceName,
          activityCode: cmd.activityCode,
          gameId: cmd.gameId,
          controllerCount: cmd.controllerIds?.length ?? cmd.controllerCount ?? 0,
          playerNumber: cmd.playerNumber,
          excludePlayerNumber: cmd.playerNumber,
          borrowed: cmd.borrowControllerIds?.length ?? 0,
        );
        // Close the current assignment AND its controller allocations at the
        // exact switch instant — the parent timer is never touched (brief §8).
        await (_db.update(_db.groupAssignments)
              ..where((t) => t.id.equals(current.id)))
            .write(GroupAssignmentsCompanion(endedAt: Value(at)));
        await _alloc.closeForAssignment(current.id, at);
        final row = await _insertAssignment(
          groupId: cmd.groupId,
          playerNumber: cmd.playerNumber,
          playerLabel: current.playerLabel,
          index: current.index + 1,
          resourceId: cmd.resourceId,
          activityCode: cmd.activityCode,
          gameId: cmd.gameId,
          controllerCount: cmd.controllerIds?.length ?? cmd.controllerCount,
          startedAt: at,
          now: now,
        );
        var moves = const <ControllerMoveRow>[];
        if (cmd.borrowControllerIds != null &&
            cmd.borrowControllerIds!.isNotEmpty) {
          moves = await _alloc.borrow(
            controllerIds: cmd.borrowControllerIds!,
            resourceId: cmd.resourceId,
            resourceName: cmd.resourceName,
            sessionRef: Controller.groupRef(cmd.groupId),
            at: at,
            now: now,
          );
        }
        var pads = const <ControllerAllocationRow>[];
        if (cmd.controllerIds != null && cmd.controllerIds!.isNotEmpty) {
          pads = await _alloc.allocate(
            scope: 'group',
            groupId: cmd.groupId,
            assignmentId: row.id,
            playerNumber: cmd.playerNumber,
            playerLabel: current.playerLabel,
            controllerIds: cmd.controllerIds!,
            resourceId: cmd.resourceId,
            resourceName: cmd.resourceName,
            activityCode: cmd.activityCode,
            gameId: cmd.gameId,
            startedAt: at,
            now: now,
          );
        }
        await _touchGroup(cmd.groupId, now);
        await _touchGame(cmd.gameId, at);
        await _sync?.record(
          kind: 'group.switch',
          entityType: 'group',
          entityId: cmd.groupId,
          payload: {
            'group_id': cmd.groupId,
            'at': Wire.at(at),
            'player_number': cmd.playerNumber,
            'expected_assignment_id': current.id,
            'assignment': _assignmentWire(row, pads, moves),
          },
        );
        return row;
      });
      return Ok(groupAssignmentFromRow(newSeg));
    } on ControllerAllocationException catch (e) {
      return Err(e.failure);
    } on _AssignBlocked catch (e) {
      return Err(e.failure);
    } catch (_) {
      return const Err(Failure(
        message: 'Could not switch that player.',
        code: 'switch_failed',
      ));
    }
  }

  @override
  Future<Result<void>> endAssignment(EndAssignmentCommand cmd) async {
    final assignments = await assignmentsFor(cmd.groupId);
    final open = assignments
        .where((a) => a.playerNumber == cmd.playerNumber && a.isOpen)
        .toList();
    if (open.isEmpty) {
      return const Err(Failure(
        message: 'That player has no active system.',
        code: 'no_open_assignment',
      ));
    }
    final at = cmd.at.toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.groupAssignments)
            ..where((t) => t.id.equals(open.first.id)))
          .write(GroupAssignmentsCompanion(endedAt: Value(at)));
      await _alloc.closeForAssignment(open.first.id, at);
      await _touchGroup(cmd.groupId, _clock.now());
      await _sync?.record(
        kind: 'group.end_player',
        entityType: 'group',
        entityId: cmd.groupId,
        payload: {
          'group_id': cmd.groupId,
          'player_number': cmd.playerNumber,
          'at': Wire.at(at),
          'expected_assignment_id': open.first.id,
        },
      );
    });
    return const Ok(null);
  }

  @override
  Future<Result<GroupSession>> extend(ExtendGroupCommand cmd) async {
    final existing = await getById(cmd.groupId);
    if (existing == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    if (!existing.isActive) {
      return const Err(Failure(
        message: 'This group session is not active.',
        fix: 'Only active groups can be extended.',
        code: 'not_active',
      ));
    }
    await _db.transaction(() async {
      final now = _clock.now();
      final ext = GroupExtensionRow(
        id: _uuid.v4(),
        groupId: cmd.groupId,
        addedMinutes: cmd.addedMinutes,
        oldEndAt: existing.scheduledEndAt,
        newEndAt: cmd.newEndAt.toUtc(),
        addedAmountPaise: cmd.addedAmountPaise,
        reason: cmd.reason,
        createdAt: now,
      );
      await _db.into(_db.groupExtensions).insert(ext);
      await (_db.update(_db.groupSessions)..where((t) => t.id.equals(cmd.groupId)))
          .write(GroupSessionsCompanion(
        scheduledEndAt: Value(cmd.newEndAt.toUtc()),
        updatedAt: Value(now),
      ));
      await _sync?.record(
        kind: 'group.extend',
        entityType: 'group',
        entityId: cmd.groupId,
        payload: {
          'group_id': cmd.groupId,
          'extension_id': ext.id,
          'added_minutes': ext.addedMinutes,
          'old_end_at': Wire.at(ext.oldEndAt),
          'new_end_at': Wire.at(ext.newEndAt),
          'added_amount_paise': ext.addedAmountPaise,
          'reason': ext.reason,
        },
      );
    });
    return Ok((await getById(cmd.groupId))!);
  }

  @override
  Future<Result<GroupSession>> end(EndGroupCommand cmd) async {
    final existing = await getById(cmd.groupId);
    if (existing == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    if (existing.status == GroupSessionStatus.completed) {
      return Ok(existing); // idempotent — no second write
    }
    if (existing.status == GroupSessionStatus.voided) {
      return const Err(Failure(
        message: 'This group was voided.',
        code: 'voided',
      ));
    }

    await _db.transaction(() async {
      final actualEnd = cmd.actualEndedAt.toUtc();
      // What this bill was priced from (stale check on the server).
      final pricedFrom = [
        for (final a in await assignmentsFor(cmd.groupId)) a.id,
      ];
      // Close every open assignment at the actual end (frees all systems).
      await (_db.update(_db.groupAssignments)
            ..where((t) => t.groupId.equals(cmd.groupId) & t.endedAt.isNull()))
          .write(GroupAssignmentsCompanion(endedAt: Value(actualEnd)));
      await _alloc.closeForGroup(cmd.groupId, actualEnd);

      final charges = [
        for (final c in cmd.charges)
          GroupChargeRow(
            id: _uuid.v4(),
            groupId: cmd.groupId,
            assignmentId: c.assignmentId,
            playerNumber: c.playerNumber,
            chargeIndex: c.chargeIndex,
            bandCode: c.bandCode,
            activityCode: c.activityCode,
            resourceId: c.resourceId,
            controllerCount: c.controllerCount,
            segmentStart: c.segmentStart,
            segmentEnd: c.segmentEnd,
            playedMinutes: c.playedMinutes,
            billedMinutes: c.billedMinutes,
            unitMinutes: c.unitMinutes,
            unitPricePaise: c.unitPricePaise,
            amountPaise: c.amountPaise,
          ),
      ];
      await _db.batch((b) => b.insertAll(_db.groupCharges, charges));

      final paid = await _totalPaid(cmd.groupId);
      final status = cmd.markWaived
          ? PaymentStatus.waived
          : _paymentStatus(billed: cmd.billedAmountPaise, paid: paid);
      await (_db.update(_db.groupSessions)..where((t) => t.id.equals(cmd.groupId)))
          .write(GroupSessionsCompanion(
        status: Value(GroupSessionStatus.completed.code),
        actualEndedAt: Value(actualEnd),
        billedAmountPaise: Value(cmd.billedAmountPaise),
        paymentStatus: Value(status.code),
        updatedAt: Value(_clock.now()),
      ));
      await _sync?.record(
        kind: 'group.end',
        entityType: 'group',
        entityId: cmd.groupId,
        payload: {
          'group_id': cmd.groupId,
          'ended_at': Wire.at(actualEnd),
          'billed_amount_paise': cmd.billedAmountPaise,
          'mark_waived': cmd.markWaived,
          'expected_assignment_ids': pricedFrom,
          'expected_scheduled_end_at': Wire.at(existing.scheduledEndAt),
          'charges': [
            for (final c in charges)
              {
                'id': c.id,
                'assignment_id': c.assignmentId,
                'player_number': c.playerNumber,
                'charge_index': c.chargeIndex,
                'band_code': c.bandCode,
                'activity_code': c.activityCode,
                'resource_id': c.resourceId,
                'controller_count': c.controllerCount,
                'segment_start': Wire.at(c.segmentStart),
                'segment_end': Wire.at(c.segmentEnd),
                'played_minutes': c.playedMinutes,
                'billed_minutes': c.billedMinutes,
                'unit_minutes': c.unitMinutes,
                'unit_price_paise': c.unitPricePaise,
                'amount_paise': c.amountPaise,
              },
          ],
        },
      );
    });
    return Ok((await getById(cmd.groupId))!);
  }

  @override
  Future<Result<GroupSession>> voidGroup(String id, String reason) async {
    final existing = await getById(id);
    if (existing == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    await _db.transaction(() async {
      final now = _clock.now();
      await (_db.update(_db.groupAssignments)
            ..where((t) => t.groupId.equals(id) & t.endedAt.isNull()))
          .write(GroupAssignmentsCompanion(endedAt: Value(now)));
      await _alloc.closeForGroup(id, now);
      await (_db.update(_db.groupSessions)..where((t) => t.id.equals(id))).write(
        GroupSessionsCompanion(
          status: Value(GroupSessionStatus.voided.code),
          voidReason: Value(reason),
          updatedAt: Value(now),
        ),
      );
      await _sync?.record(
        kind: 'group.void',
        entityType: 'group',
        entityId: id,
        payload: {'group_id': id, 'reason': reason, 'at': Wire.at(now)},
      );
    });
    return Ok((await getById(id))!);
  }

  // --- history + payments ----------------------------------------------------

  @override
  Future<List<GroupExtension>> extensionsFor(String groupId) async {
    final rows = await (_db.select(_db.groupExtensions)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    return rows.map(groupExtensionFromRow).toList();
  }

  @override
  Future<List<GroupCharge>> chargesFor(String groupId) async {
    final rows = await (_db.select(_db.groupCharges)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm(expression: t.chargeIndex)]))
        .get();
    return rows.map(groupChargeFromRow).toList();
  }

  @override
  Future<List<GroupPayment>> paymentsFor(String groupId) async =>
      (await _paymentsQuery(groupId).get()).map(groupPaymentFromRow).toList();

  @override
  Stream<List<GroupPayment>> watchPaymentsFor(String groupId) => _paymentsQuery(
          groupId)
      .watch()
      .map((r) => r.map(groupPaymentFromRow).toList());

  SimpleSelectStatement<$GroupPaymentsTable, GroupPaymentRow> _paymentsQuery(
          String groupId) =>
      _db.select(_db.groupPayments)
        ..where((t) => t.groupId.equals(groupId))
        ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);

  @override
  Future<Result<GroupPayment>> recordPayment(
      RecordGroupPaymentCommand cmd) async {
    if (cmd.isRefund && (cmd.reason == null || cmd.reason!.trim().isEmpty)) {
      return const Err(Failure(
        message: 'A refund needs a reason.',
        fix: 'Add why the money is being returned.',
        code: 'refund_reason_required',
      ));
    }
    final amount =
        signedPaymentAmount(cmd.amountPaise, isRefund: cmd.isRefund);
    if (amount.isErr) return Err(amount.failureOrNull!);
    final signed = amount.valueOrNull!;
    final group = await getById(cmd.groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    final row = await _db.transaction(() async {
      final now = _clock.now();
      final payment = GroupPaymentRow(
        id: _uuid.v4(),
        groupId: cmd.groupId,
        amountPaise: signed,
        method: cmd.method.code,
        isRefund: cmd.isRefund,
        note: cmd.note,
        reason: cmd.reason,
        createdAt: now,
      );
      await _db.into(_db.groupPayments).insert(payment);
      await _sync?.record(
        kind: 'payment.record',
        entityType: 'group',
        entityId: cmd.groupId,
        payload: {
          'scope': 'group',
          'parent_id': cmd.groupId,
          'payment_id': payment.id,
          'amount_paise': payment.amountPaise,
          'method': payment.method,
          'is_refund': payment.isRefund,
          'note': payment.note,
          'reason': payment.reason,
        },
      );
      if (group.paymentStatus != PaymentStatus.waived) {
        final paid = await _totalPaid(cmd.groupId);
        final status =
            _paymentStatus(billed: group.billedAmountPaise, paid: paid);
        await (_db.update(_db.groupSessions)
              ..where((t) => t.id.equals(cmd.groupId)))
            .write(GroupSessionsCompanion(
          paymentStatus: Value(status.code),
          updatedAt: Value(now),
        ));
      }
      return payment;
    });
    return Ok(groupPaymentFromRow(row));
  }

  // --- helpers ---------------------------------------------------------------

  /// Throws [_AssignBlocked] when [resourceId] can't host this assignment, after
  /// looking at BOTH open single-session segments and open group assignments.
  Future<void> _ensureAssignable({
    required String groupId,
    required String resourceId,
    required String resourceName,
    required String activityCode,
    required String? gameId,
    required int controllerCount,
    required int playerNumber,
    int? excludePlayerNumber,
    int borrowed = 0,
  }) async {
    // The station must be one that may take a session at all. Same rule as a
    // single session: the pickers filter by status, but a sheet can be open
    // when a station is sent for maintenance.
    final resourceRow = await (_db.select(_db.resources)
          ..where((t) => t.id.equals(resourceId)))
        .getSingleOrNull();
    if (resourceRow == null) {
      throw _AssignBlocked(Failure(
        message: '$resourceName no longer exists.',
        fix: 'Pick another system.',
        code: 'resource_missing',
      ));
    }
    final resourceStatus = ResourceStatus.fromCode(resourceRow.status);
    if (resourceStatus != ResourceStatus.available) {
      throw _AssignBlocked(Failure(
        message: '$resourceName is marked '
            '${resourceStatus.label.toLowerCase()}.',
        fix: 'Pick another system, or make it available in '
            'Settings → Stations.',
        code: 'resource_unavailable',
      ));
    }

    // RIFT and any dual-capability station may be locked to one activity
    // (brief §1): a mode-locked station only takes its locked activity.
    if (resourceRow.currentMode != null &&
        resourceRow.currentMode != activityCode) {
      throw _AssignBlocked(Failure(
        message: '$resourceName is set to ${resourceRow.currentMode} mode.',
        fix: 'Switch $resourceName in Settings → Stations, or use another system.',
        code: 'mode_locked',
      ));
    }

    // A chosen game must be playable on this system (group feature §6). Absence
    // of a compatibility row means the game is not installed there.
    if (gameId != null) {
      final compat = await (_db.select(_db.gameResources)
            ..where((t) =>
                t.gameId.equals(gameId) & t.resourceId.equals(resourceId)))
          .getSingleOrNull();
      final status = compat == null
          ? GameAvailability.notInstalled
          : GameAvailability.fromCode(compat.status);
      if (status != GameAvailability.playable) {
        throw _AssignBlocked(Failure(
          message: '$resourceName can\'t run this game (${status.label}).',
          fix: 'Pick a system where the game is playable, or change the game.',
          code: 'not_playable',
        ));
      }
    }

    // A single session on this resource always blocks a group (group §7).
    final singleBusy = await (_db.select(_db.sessionSegments)
          ..where((t) => t.resourceId.equals(resourceId) & t.endedAt.isNull()))
        .getSingleOrNull();
    if (singleBusy != null) {
      throw _AssignBlocked(_busyFailure(resourceName));
    }

    final here = await (_db.select(_db.groupAssignments)
          ..where((t) => t.resourceId.equals(resourceId) & t.endedAt.isNull()))
        .get();
    final others = [
      for (final a in here)
        if (!(a.groupId == groupId &&
            excludePlayerNumber != null &&
            a.playerNumber == excludePlayerNumber))
          a,
    ];
    // A station is never shared across groups. Checked first so a cross-group
    // conflict reads as "in use by another group", not a capacity error.
    if (others.any((a) => a.groupId != groupId)) {
      throw _AssignBlocked(Failure(
        message: '$resourceName is in use by another group.',
        fix: 'Pick another system.',
        code: 'resource_busy',
      ));
    }

    // Absolute hardware ceilings — enforced for EVERY assignment, including the
    // first/only occupant of a station (the early return below only skips the
    // shared-station rules). `others` are all same-group here, so `used` is the
    // pads this group already holds on the station; it is the stored count,
    // which the callers keep equal to the allocated pad count.
    final used = others.fold<int>(0, (s, a) => s + (a.controllerCount ?? 0));
    if (used + controllerCount > portCapacity) {
      throw _AssignBlocked(Failure(
        message: '$resourceName can hold up to $portCapacity controllers.',
        fix: 'Reduce controllers or use another system.',
        code: 'controllers_exceeded',
      ));
    }
    // Every controller on a station is a local player slot: the game's
    // local-player limit bounds the controllers there (the rule a single
    // session follows), whether one player holds them or several share it.
    if (gameId != null) {
      final game = await (_db.select(_db.games)
            ..where((t) => t.id.equals(gameId)))
          .getSingleOrNull();
      final maxPlayers = game?.maxLocalPlayers ?? 1;
      if (used + controllerCount > maxPlayers) {
        throw _AssignBlocked(Failure(
          message: '${game?.name ?? 'This game'} supports $maxPlayers local '
              'player${maxPlayers == 1 ? '' : 's'} — '
              '${used + controllerCount} controllers on $resourceName.',
          fix: 'Use fewer controllers on $resourceName, or move a player to '
              'another system.',
          code: 'players_exceeded',
        ));
      }
    }

    // Pads being borrowed in this same operation arrive before allocation.
    final usable = await _usableControllersAt(resourceId) + borrowed;
    if (used + controllerCount > usable) {
      throw _AssignBlocked(Failure(
        message: '$resourceName has only $usable usable '
            'controller${usable == 1 ? '' : 's'}'
            '${used == 0 ? '' : ' ($used already in use)'}.',
        fix: 'Move a controller to $resourceName, or use another system.',
        code: 'controllers_unavailable',
      ));
    }

    // The remaining rules only matter when this player shares the station.
    if (others.isEmpty) return;

    if (!await _activityAllowsSharing(activityCode)) {
      throw _AssignBlocked(_busyFailure(resourceName));
    }

    if (others.any((a) => a.activityCode != activityCode || a.gameId != gameId)) {
      throw _AssignBlocked(Failure(
        message: 'Players sharing $resourceName must play the same game.',
        fix: 'Match the game already running there, or use another system.',
        code: 'game_conflict',
      ));
    }

    // Supported local players for a shared station (brief §6): never assume 4.
    if (gameId != null) {
      final game = await (_db.select(_db.games)..where((t) => t.id.equals(gameId)))
          .getSingleOrNull();
      final maxPlayers = game?.maxLocalPlayers ?? 1;
      final players = {for (final a in others) a.playerNumber, playerNumber};
      if (players.length > maxPlayers) {
        throw _AssignBlocked(Failure(
          message: 'This game supports $maxPlayers local '
              'player${maxPlayers == 1 ? '' : 's'} on one system.',
          fix: 'Use another system for the extra '
              'player${maxPlayers == 1 ? '' : 's'}.',
          code: 'players_exceeded',
        ));
      }
    }
  }

  /// Usable pads physically present at a station.
  Future<int> _usableControllersAt(String resourceId) async {
    final rows = await (_db.select(_db.controllers)
          ..where((t) =>
              t.currentResourceId.equals(resourceId) &
              t.status.equals(ControllerStatus.usable.code)))
        .get();
    return rows.length;
  }

  Future<bool> _activityAllowsSharing(String activityCode) async {
    final a = await (_db.select(_db.activities)
          ..where((t) => t.code.equals(activityCode)))
        .getSingleOrNull();
    return a?.usesControllers ?? false;
  }

  Future<GroupAssignmentRow> _insertAssignment({
    required String groupId,
    required int playerNumber,
    required String? playerLabel,
    required int index,
    required String resourceId,
    required String activityCode,
    required String? gameId,
    required int? controllerCount,
    required DateTime startedAt,
    required DateTime now,
  }) async {
    final row = GroupAssignmentRow(
      id: _uuid.v4(),
      groupId: groupId,
      playerNumber: playerNumber,
      playerLabel: playerLabel,
      index: index,
      resourceId: resourceId,
      activityCode: activityCode,
      gameId: gameId,
      controllerCount: controllerCount,
      startedAt: startedAt,
      endedAt: null,
      createdAt: now,
    );
    await _db.into(_db.groupAssignments).insert(row);
    return row;
  }

  Future<void> _touchGroup(String groupId, DateTime now) async {
    await (_db.update(_db.groupSessions)..where((t) => t.id.equals(groupId)))
        .write(GroupSessionsCompanion(updatedAt: Value(now)));
  }

  Future<void> _touchGame(String? gameId, DateTime at) async {
    if (gameId == null) return;
    await (_db.update(_db.games)..where((t) => t.id.equals(gameId)))
        .write(GamesCompanion(lastPlayedAt: Value(at)));
  }

  Future<int> _totalPaid(String groupId) async {
    final rows = await (_db.select(_db.groupPayments)
          ..where((t) => t.groupId.equals(groupId)))
        .get();
    return rows.fold<int>(0, (sum, p) => sum + p.amountPaise);
  }

  PaymentStatus _paymentStatus({required int? billed, required int paid}) {
    if (billed == null) {
      return paid > 0 ? PaymentStatus.partial : PaymentStatus.unpaid;
    }
    if (paid >= billed) return PaymentStatus.paid;
    if (paid > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }

  Failure _busyFailure(String resourceName) => Failure(
        message: '$resourceName is in use.',
        fix: 'Pick another system.',
        code: 'resource_busy',
      );
}

class _AssignBlocked implements Exception {
  _AssignBlocked(this.failure);
  final Failure failure;
}
