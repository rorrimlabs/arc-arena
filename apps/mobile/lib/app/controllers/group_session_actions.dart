/// Application-layer orchestration for group sessions (group feature §1–§9).
/// Wires the pure services (planner, group availability, group billing) to the
/// repositories and the clock. The UI calls these; it never prices, checks
/// availability, or computes timestamps itself.
library;

import 'dart:async';

import 'package:arena_ops/app/controllers/pad_board_loader.dart';
import 'package:arena_ops/app/controllers/session_actions.dart'
    show resolveControllerChoice;
import 'package:arena_ops/app/notifications/session_reminders.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/repositories/controller_allocation_reader.dart';
import 'package:arena_ops/domain/repositories/group_commands.dart';
import 'package:arena_ops/domain/repositories/group_session_repository.dart';
import 'package:arena_ops/domain/repositories/session_repository.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/services/group_availability_service.dart';
import 'package:arena_ops/domain/services/group_billing.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// One player's in-progress choice while building a group session. The
/// player's controllers live in ONE value, [controllers] (count + pads).
@immutable
class GroupPlayerDraft {
  GroupPlayerDraft({
    required this.playerNumber,
    this.playerLabel,
    this.resourceId,
    this.resourceName,
    this.activityCode,
    this.gameId,
    this.gameName,
    ControllerChoice? controllers,
    int? controllerCount,
    List<String>? controllerIds,
  }) : controllers = resolveControllerChoice(
         controllers,
         controllerCount,
         controllerIds,
       );

  final int playerNumber;
  final String? playerLabel;
  final String? resourceId;
  final String? resourceName;
  final String? activityCode;
  final String? gameId;
  final String? gameName;
  final ControllerChoice controllers;

  /// Billed controllers for this player — derived from [controllers].
  int? get controllerCount => controllers.count;
  List<String> get controllerIds => controllers.padIds;

  bool get isComplete => resourceId != null && activityCode != null;

  GroupPlayerDraft copyWith({
    String? playerLabel,
    String? resourceId,
    String? resourceName,
    String? activityCode,
    String? gameId,
    String? gameName,
    ControllerChoice? controllers,
    bool clearGame = false,
  }) => GroupPlayerDraft(
    playerNumber: playerNumber,
    playerLabel: playerLabel ?? this.playerLabel,
    resourceId: resourceId ?? this.resourceId,
    resourceName: resourceName ?? this.resourceName,
    activityCode: activityCode ?? this.activityCode,
    gameId: clearGame ? null : (gameId ?? this.gameId),
    gameName: clearGame ? null : (gameName ?? this.gameName),
    controllers: controllers ?? this.controllers,
  );
}

/// The in-progress choices for a new group session.
@immutable
class GroupSessionDraft {
  const GroupSessionDraft({
    this.primaryCustomerId,
    this.playerCount = 2,
    this.purchasedControllerCount = 2,
    this.durationMinutes = 60,
    this.openEnded = false,
    this.players = const [],
  });

  final String? primaryCustomerId;
  final int playerCount;
  final int purchasedControllerCount;
  final int? durationMinutes;
  final bool openEnded;
  final List<GroupPlayerDraft> players;

  GroupSessionDraft copyWith({
    String? primaryCustomerId,
    int? playerCount,
    int? purchasedControllerCount,
    int? durationMinutes,
    bool? openEnded,
    List<GroupPlayerDraft>? players,
  }) => GroupSessionDraft(
    primaryCustomerId: primaryCustomerId ?? this.primaryCustomerId,
    playerCount: playerCount ?? this.playerCount,
    purchasedControllerCount:
        purchasedControllerCount ?? this.purchasedControllerCount,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    openEnded: openEnded ?? this.openEnded,
    players: players ?? this.players,
  );
}

/// The result of planning a new group: the shared window plus the estimate.
@immutable
class GroupStartPlan {
  const GroupStartPlan({
    required this.startedAt,
    required this.scheduledEndAt,
    required this.openEnded,
    required this.estimate,
    required this.billingMode,
    this.lines = const [],
  });

  final DateTime startedAt;
  final DateTime scheduledEndAt;
  final bool openEnded;
  final Paise estimate;
  final GroupBillingMode billingMode;

  /// Per-system breakdown of [estimate] (each system's own charges summed).
  final List<GroupEstimateLine> lines;
}

/// One line of a group estimate: a system (or the pooled controllers), the
/// controllers on it, the minutes billed and the amount — before the single
/// cash rounding applied to the group total.
@immutable
class GroupEstimateLine {
  const GroupEstimateLine({
    required this.label,
    required this.controllerCount,
    required this.minutes,
    required this.amount,
  });
  final String label;
  final int? controllerCount;
  final int minutes;
  final Paise amount;
}

/// The result of planning a group extension (group feature §8).
@immutable
class GroupExtensionPlan {
  const GroupExtensionPlan({
    required this.oldEnd,
    required this.newEnd,
    required this.addedMinutes,
    required this.addedCost,
  });

  final DateTime oldEnd;
  final DateTime newEnd;
  final int addedMinutes;
  final Paise addedCost;
}

class GroupSessionActions {
  GroupSessionActions({
    required this.groups,
    required this.sessions,
    required this.catalog,
    required this.bookings,
    required this.clock,
    this.guard = const PermissionGuard(null),
    this.availability = const AvailabilityService(),
    this.groupAvailability = const GroupAvailabilityService(),
    this.billing = const GroupBilling(),
    this.reminders,
    this.pads,
    this.padSelection = const PadSelection(),
  });

  final GroupSessionRepository groups;
  final SessionRepository sessions;
  final CatalogRepository catalog;

  /// Read to keep a group off a station someone has reserved.
  final BookingRepository bookings;
  final Clock clock;

  /// Optional session timer reminders orchestrator (spec §23).
  final SessionReminders? reminders;

  /// Same gate as single sessions: a group takes money and occupies stations,
  /// so it is checked underneath the UI. Defaults to "nobody".
  final PermissionGuard guard;
  final AvailabilityService availability;
  final GroupAvailabilityService groupAvailability;
  final GroupBilling billing;

  /// Who holds which pad. Optional so count-only callers need not wire it;
  /// without it a game change cannot carry a player's pads across.
  final ControllerAllocationReader? pads;
  final PadSelection padSelection;

  /// Pads a player's current assignment holds, in a stable order.
  Future<List<String>> padsHeldBy(GroupAssignment assignment) async => [
    for (final a
        in await pads?.openPadAllocations() ?? const <OpenPadAllocation>[])
      if (a.assignmentId == assignment.id) a.controllerId,
  ]..sort();

  Future<String> _resourceName(String id) async {
    for (final r in await catalog.resources()) {
      if (r.id == id) return r.name;
    }
    return id;
  }

  /// A station locked to another activity (RIFT in VR mode) — said early; the
  /// repository enforces it too.
  Future<Failure?> _modeLock(String resourceId, String activityCode) async {
    for (final r in await catalog.resources()) {
      if (r.id == resourceId &&
          r.currentMode != null &&
          r.currentMode != activityCode) {
        return Failure(
          message: '${r.name} is set to ${r.currentMode} mode.',
          fix:
              'Switch ${r.name} to $activityCode in Settings → Stations, '
              'or use another system.',
          code: 'mode_locked',
        );
      }
    }
    return null;
  }

  PadBoardLoader get boards => PadBoardLoader(
    catalog: catalog,
    sessions: sessions,
    groups: groups,
    pads: pads,
  );

  /// Pads other players of [groupId] hold right now, labelled for messages.
  Future<Map<String, String>> _teammatePads(String groupId, int player) async =>
      {
        for (final a
            in await pads?.openPadAllocations() ?? const <OpenPadAllocation>[])
          if (a.groupId == groupId && a.playerNumber != player)
            a.controllerId: 'Player ${a.playerNumber}',
      };

  /// Friendly pre-flight of one player's [ControllerChoice]. [pickedForOthers]
  /// carries pads already chosen for other players so a pad can never be
  /// promised to two players. The game limit is checked per station by the
  /// repository (players sharing it), so it is not applied per player here.
  Future<Failure?> checkControllers({
    required ControllerChoice choice,
    required String resourceId,
    required String resourceName,
    required String activityCode,
    Set<String> keepIds = const {},
    Map<String, String> pickedForOthers = const {},
    String? exceptOccupantId,
    bool legacyUnchanged = false,
  }) async {
    final activity = (await catalog.activities())
        .where((a) => a.code == activityCode)
        .firstOrNull;
    if (!(activity?.usesControllers ?? false)) return null;
    final board = await boards.load(
      resourceId: resourceId,
      resourceName: resourceName,
      keepIds: keepIds,
      pickedForOthers: pickedForOthers,
      exceptOccupantId: exceptOccupantId,
    );
    return padSelection.check(
      choice,
      board,
      requireSupply: !(legacyUnchanged && !choice.isTracked),
    );
  }

  /// Usable controllers physically present at each station, keyed by resource
  /// id. The *supply* side of allocation; what open sessions already commit is
  /// handled by the availability rules.
  Future<Map<String, int>> _usableControllersByStation() async {
    final counts = <String, int>{};
    for (final c in await catalog.controllers()) {
      if (!c.status.isUsable) continue;
      counts[c.currentResourceId] = (counts[c.currentResourceId] ?? 0) + 1;
    }
    return counts;
  }

  DateTime _closeAt(DateTime at, BusinessCalendar calendar) =>
      calendar.operatingWindow(IstDate.fromUtc(at))?.end ??
      at.add(const Duration(hours: 12));

  /// The shared countdown for a group — driven only by the parent's stored
  /// timestamps, never a counter (group feature §3).
  /// [warn] is the arena's end-of-session warning (floor options).
  SessionTimer groupTimer(
    GroupSession g, {
    Duration warn = const Duration(minutes: 5),
  }) => SessionTimer(
    startedAt: g.startedAt,
    scheduledEndAt: g.scheduledEndAt,
    actualEndedAt: g.actualEndedAt,
    warnThreshold: warn,
  );

  // --- occupancy helpers -----------------------------------------------------

  /// Single sessions **and** reservations holding a station over [window].
  ///
  /// A group spread across four stations over the top of a reservation is the
  /// same double-booking as a walk-in doing it, so bookings are checked here
  /// too. `overlapping` returns only still-open (`booked`) reservations, and an
  /// any-system booking holds no particular station until check-in.
  Future<List<Occupancy>> _singleOccupancies(UtcInterval window) async {
    final active = await sessions.active();
    final booked = await bookings.overlapping(window.start, window.end);
    return [
      for (final a in active)
        Occupancy(
          resourceId: a.current.resourceId,
          interval: UtcInterval(a.current.startedAt, a.session.scheduledEndAt),
          isBooking: false,
          label: 'session',
        ),
      for (final b in booked)
        if (b.resourceId != null)
          Occupancy(
            resourceId: b.resourceId!,
            interval: UtcInterval(b.scheduledStart, b.scheduledEnd),
            isBooking: true,
            label: b.partyName,
          ),
    ];
  }

  /// Open group assignments, optionally excluding one group (when extending or
  /// switching inside it).
  Future<List<GroupAssignment>> _openGroupAssignments({
    String? excludeGroupId,
  }) async {
    final open = await groups.openAssignments();
    return [
      for (final a in open)
        if (a.groupId != excludeGroupId) a,
    ];
  }

  // --- create ----------------------------------------------------------------

  /// Price preview + availability for a new group (group feature §1–§2).
  Future<Result<GroupStartPlan>> previewCreate(GroupSessionDraft d) async {
    if (d.primaryCustomerId == null) {
      return const Err(
        Failure(message: 'Pick the primary customer.', code: 'incomplete'),
      );
    }
    final assigned = d.players.where((p) => p.isComplete).toList();
    if (assigned.isEmpty) {
      return const Err(
        Failure(
          message: 'Assign at least one player to a system.',
          code: 'no_assignments',
        ),
      );
    }

    final snapshot = await catalog.currentSnapshot();
    final now = clock.now();
    final scheduledEnd = d.openEnded
        ? _closeAt(now, snapshot.calendar)
        : now.add(Duration(minutes: d.durationMinutes ?? 60));
    if (!scheduledEnd.isAfter(now)) {
      return const Err(
        Failure(message: 'Choose a duration.', code: 'invalid_duration'),
      );
    }
    final window = UtcInterval(now, scheduledEnd);
    final closeAt = _closeAt(now, snapshot.calendar);
    final singleOcc = await _singleOccupancies(window);
    final otherGroups = await _openGroupAssignments();
    final activities = await catalog.activities();
    final usable = await _usableControllersByStation();

    // Validate each assignment, treating earlier drafts in this create as
    // already on their system so in-create co-location is checked too.
    final draftAssignments = <GroupAssignment>[];
    final pickedSoFar = <String, String>{};
    for (final p in assigned) {
      final who = p.playerLabel ?? 'Player ${p.playerNumber}';
      final locked = await _modeLock(p.resourceId!, p.activityCode!);
      if (locked != null) return Err(locked);
      final f = await checkControllers(
        choice: p.controllers,
        resourceId: p.resourceId!,
        resourceName: p.resourceName ?? p.resourceId!,
        activityCode: p.activityCode!,
        pickedForOthers: pickedSoFar,
      );
      if (f != null) {
        return Err(
          Failure(message: '$who: ${f.message}', fix: f.fix, code: f.code),
        );
      }
      for (final id in p.controllerIds) {
        pickedSoFar[id] = who;
      }
      final availabilityStatus = p.gameId == null
          ? GameAvailability.playable
          : await catalog.availabilityOf(p.gameId!, p.resourceId!);
      final game = p.gameId == null ? null : await catalog.gameById(p.gameId!);
      final activity = activities.firstWhere(
        (a) => a.code == p.activityCode,
        orElse: () => throw StateError('unknown activity ${p.activityCode}'),
      );
      final check = groupAvailability.canAssign(
        resourceId: p.resourceId!,
        resourceName: p.resourceName ?? p.resourceId!,
        groupId: '__new__',
        activityCode: p.activityCode!,
        gameId: p.gameId,
        controllerCount: p.controllerCount ?? 0,
        // Pads borrowed for this player arrive at the station before allocation.
        usableControllers:
            (usable[p.resourceId!] ?? 0) + p.controllers.borrowIds.length,
        gameAvailability: availabilityStatus,
        maxLocalPlayers: game?.maxLocalPlayers ?? 1,
        gameName: game?.name,
        activityAllowsSharing: activity.usesControllers,
        singleOccupancies: singleOcc,
        openOnResource: [...otherGroups, ...draftAssignments],
        playerNumber: p.playerNumber,
        window: window,
        closeAt: closeAt,
        allowPastClose: snapshot.policy.allowExtendPastClose,
      );
      if (check.isErr) {
        final f = check.failureOrNull!;
        return Err(
          Failure(message: '$who: ${f.message}', fix: f.fix, code: f.code),
        );
      }

      draftAssignments.add(
        GroupAssignment(
          id: 'draft_${p.playerNumber}_${draftAssignments.length}',
          groupId: '__new__',
          playerNumber: p.playerNumber,
          index: 0,
          resourceId: p.resourceId!,
          activityCode: p.activityCode!,
          gameId: p.gameId,
          controllerCount: p.controllerCount,
          startedAt: now,
          createdAt: now,
        ),
      );
    }

    final bill = billing.bill(
      snapshot: snapshot,
      assignments: draftAssignments,
      mode: snapshot.policy.groupBillingMode,
      purchasedControllerCount: d.purchasedControllerCount,
      groupStart: now,
      openEndAt: scheduledEnd,
    );

    final names = {for (final r in await catalog.resources()) r.id: r.name};
    return Ok(
      GroupStartPlan(
        startedAt: now,
        scheduledEndAt: scheduledEnd,
        openEnded: d.openEnded,
        estimate: bill.total,
        billingMode: snapshot.policy.groupBillingMode,
        lines: estimateLines(bill, names),
      ),
    );
  }

  /// Sums a group bill's charge rows into one line per system (and controller
  /// count on it), so staff see what each system contributes.
  static List<GroupEstimateLine> estimateLines(
    GroupBill bill,
    Map<String, String> names,
  ) {
    final byKey = <String, ({String label, int? n, int minutes, int paise})>{};
    for (final c in bill.charges) {
      final label = c.resourceId == null
          ? 'Shared controllers'
          : names[c.resourceId] ?? c.resourceId!;
      final key = '$label|${c.controllerCount}';
      final prev = byKey[key];
      byKey[key] = (
        label: label,
        n: c.controllerCount,
        minutes: (prev?.minutes ?? 0) + c.billedMinutes,
        paise: (prev?.paise ?? 0) + c.amountPaise,
      );
    }
    return [
      for (final v in byKey.values)
        GroupEstimateLine(
          label: v.label,
          controllerCount: v.n,
          minutes: v.minutes,
          amount: Paise(v.paise),
        ),
    ];
  }

  /// Starts the parent group and all its initial assignments.
  Future<Result<GroupSession>> create(GroupSessionDraft d) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    final preview = await previewCreate(d);
    if (preview.isErr) return Err(preview.failureOrNull!);
    final plan = preview.valueOrNull!;
    final snapshot = await catalog.currentSnapshot();
    final res = await groups.create(
      CreateGroupCommand(
        primaryCustomerId: d.primaryCustomerId!,
        playerCount: d.playerCount,
        purchasedControllerCount: d.purchasedControllerCount,
        startedAt: plan.startedAt,
        scheduledEndAt: plan.scheduledEndAt,
        snapshot: snapshot,
        billingMode: plan.billingMode,
        assignments: [
          for (final p in d.players.where((p) => p.isComplete))
            GroupAssignmentDraft(
              playerNumber: p.playerNumber,
              playerLabel: p.playerLabel,
              resourceId: p.resourceId!,
              resourceName: p.resourceName ?? p.resourceId!,
              activityCode: p.activityCode!,
              gameId: p.gameId,
              controllerCount: p.controllers.count,
              controllerIds: p.controllers.padIdsOrNull,
              borrowControllerIds: p.controllers.borrowIdsOrNull,
            ),
        ],
      ),
    );
    if (res.isOk) {
      unawaited(reminders?.scheduleForGroup(res.valueOrNull!));
      AppTelemetry.timerStarted(
        sessionId: res.valueOrNull!.id,
        resourceId: d.players.firstOrNull?.resourceId ?? 'group',
        activityCode: d.players.firstOrNull?.activityCode ?? 'GROUP',
        durationMinutes: d.openEnded ? null : d.durationMinutes,
        controllerCount: d.purchasedControllerCount,
        isGroup: true,
      );
    }
    return res;
  }

  // --- live bill -------------------------------------------------------------

  /// Live amount so far, billed across all assignments by the group's mode.
  GroupBill liveBill(ActiveGroupSession g, DateTime now) => billing.bill(
    snapshot: g.group.snapshot,
    assignments: g.assignments,
    mode: g.group.billingMode,
    purchasedControllerCount: g.group.purchasedControllerCount,
    groupStart: g.group.startedAt,
    openEndAt: now,
  );

  // --- candidate systems for switch / add (group feature §5–§6) --------------

  /// Resources a player may move to (or a new player may join): compatible with
  /// the activity, operational, and not blocked by a single session, another
  /// group, or an incompatible co-location.
  Future<List<Resource>> candidateResources({
    required GroupSession group,
    required int playerNumber,
    required String activityCode,
    String? gameId,
    int controllerCount = 1,
    bool staying = false,
  }) async {
    final resources = await catalog.resources();
    final activities = await catalog.activities();
    final activity = activities.firstWhere(
      (a) => a.code == activityCode,
      orElse: () => activities.first,
    );
    final now = clock.now();
    final window = UtcInterval(now, group.scheduledEndAt);
    final singleOcc = await _singleOccupancies(window);
    final openGroup = await groups.openAssignments();
    final snapshot = await catalog.currentSnapshot();
    final closeAt = _closeAt(now, snapshot.calendar);

    final out = <Resource>[];
    for (final r in resources) {
      if (!r.activityCodes.contains(activityCode)) continue;
      if (r.status != ResourceStatus.available) continue;
      if (r.currentMode != null && r.currentMode != activityCode) continue;
      final availabilityStatus = gameId == null
          ? GameAvailability.playable
          : await catalog.availabilityOf(gameId, r.id);
      final game = gameId == null ? null : await catalog.gameById(gameId);
      final check = groupAvailability.canAssign(
        resourceId: r.id,
        resourceName: r.name,
        groupId: group.id,
        activityCode: activityCode,
        gameId: gameId,
        controllerCount: controllerCount,
        // Whether the STATION can take the player is separate from whether
        // its own pads are there: pads can be borrowed in, and the picker /
        // previewAssignment check the actual pads. Only the hardware port
        // ceiling and the game limit apply here.
        usableControllers: PadSelection.portCapacity,
        gameAvailability: availabilityStatus,
        maxLocalPlayers: game?.maxLocalPlayers ?? 1,
        gameName: game?.name,
        activityAllowsSharing: activity.usesControllers,
        singleOccupancies: singleOcc,
        openOnResource: openGroup,
        playerNumber: playerNumber,
        excludePlayerNumber: staying ? playerNumber : null,
        window: window,
        closeAt: closeAt,
        allowPastClose: snapshot.policy.allowExtendPastClose,
      );
      if (check.isOk) out.add(r);
    }
    return out;
  }

  /// The whole pre-flight for putting ONE player on a system — adding them,
  /// switching them, or changing their game or controllers — run live by the
  /// sheets so a problem shows (and Apply stays disabled) BEFORE anything is
  /// saved: RIFT mode lock, the picked pads, game playable on that system,
  /// teammates sharing it on the same game, and the game's local-player limit
  /// over every controller on the station. The repository re-checks on save.
  ///
  /// [current] is the player's open assignment when they already have one (it
  /// is being replaced, so it does not count against the station).
  Future<Result<void>> previewAssignment({
    required GroupSession group,
    required int playerNumber,
    required String resourceId,
    required String resourceName,
    required String activityCode,
    String? gameId,
    required ControllerChoice controllers,
    GroupAssignment? current,
  }) async {
    final locked = await _modeLock(resourceId, activityCode);
    if (locked != null) return Err(locked);
    final padProblem = await checkControllers(
      choice: controllers,
      resourceId: resourceId,
      resourceName: resourceName,
      activityCode: activityCode,
      keepIds: current == null ? const {} : (await padsHeldBy(current)).toSet(),
      pickedForOthers: await _teammatePads(group.id, playerNumber),
      exceptOccupantId: current?.id,
      legacyUnchanged:
          current != null &&
          current.resourceId == resourceId &&
          (controllers.count ?? 0) <= (current.controllerCount ?? 0),
    );
    if (padProblem != null) return Err(padProblem);

    final activities = await catalog.activities();
    final activity = activities
        .where((a) => a.code == activityCode)
        .firstOrNull;
    final game = gameId == null ? null : await catalog.gameById(gameId);
    final now = clock.now();
    final snapshot = await catalog.currentSnapshot();
    final usable = await _usableControllersByStation();
    // The player's own pads already standing at this station are counted in
    // [usable]; pads being borrowed arrive with the change.
    return groupAvailability.canAssign(
      resourceId: resourceId,
      resourceName: resourceName,
      groupId: group.id,
      activityCode: activityCode,
      gameId: gameId,
      controllerCount: controllers.count ?? 0,
      usableControllers:
          (usable[resourceId] ?? 0) + controllers.borrowIds.length,
      gameAvailability: gameId == null
          ? GameAvailability.playable
          : await catalog.availabilityOf(gameId, resourceId),
      maxLocalPlayers: game?.maxLocalPlayers ?? 1,
      gameName: game?.name,
      activityAllowsSharing: activity?.usesControllers ?? false,
      singleOccupancies: await _singleOccupancies(
        UtcInterval(now, group.scheduledEndAt),
      ),
      openOnResource: await groups.openAssignments(),
      playerNumber: playerNumber,
      excludePlayerNumber: current == null ? null : playerNumber,
      window: UtcInterval(now, group.scheduledEndAt),
      closeAt: _closeAt(now, snapshot.calendar),
      allowPastClose: true, // the group's window is already running
    );
  }

  Future<GroupSession?> _group(String id) => groups.getById(id);

  // --- in-session changes (per player) ---------------------------------------

  Future<Result<GroupAssignment>> switchSystem({
    required String groupId,
    required int playerNumber,
    required String resourceId,
    required String resourceName,
    required String activityCode,
    String? gameId,
    ControllerChoice? controllers,
    int? controllerCount,
    List<String>? controllerIds,
    GroupAssignment? current,
    DateTime? at,
  }) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    final choice = resolveControllerChoice(
      controllers,
      controllerCount,
      controllerIds,
    );
    final group = await _group(groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    final f = await previewAssignment(
      group: group,
      playerNumber: playerNumber,
      resourceId: resourceId,
      resourceName: resourceName,
      activityCode: activityCode,
      gameId: gameId,
      controllers: choice,
      // A switch always replaces the player's open assignment, even when the
      // caller did not pass it.
      current:
          current ??
          (await groups.activeGroups())
              .where((g) => g.group.id == groupId)
              .firstOrNull
              ?.currentForPlayer(playerNumber),
    );
    if (f.isErr) return Err(f.failureOrNull!);
    return groups.switchAssignment(
      SwitchAssignmentCommand(
        groupId: groupId,
        playerNumber: playerNumber,
        at: at ?? clock.now(),
        resourceId: resourceId,
        resourceName: resourceName,
        activityCode: activityCode,
        gameId: gameId,
        controllerCount: choice.count,
        controllerIds: choice.padIdsOrNull,
        borrowControllerIds: choice.borrowIdsOrNull,
      ),
    );
  }

  Future<Result<GroupAssignment>> changeGame({
    required String groupId,
    required GroupAssignment current,
    required String? gameId,
    DateTime? at,
  }) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    // The player keeps the same pads through a game change (brief §8).
    final held = await padsHeldBy(current);
    final name = await _resourceName(current.resourceId);
    final group = await _group(groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    // Before anything is saved: the new game must be playable here, match any
    // teammates sharing the system, and fit every controller on it.
    final f = await previewAssignment(
      group: group,
      playerNumber: current.playerNumber,
      resourceId: current.resourceId,
      resourceName: name,
      activityCode: current.activityCode,
      gameId: gameId,
      controllers: held.isEmpty
          ? ControllerChoice.count(current.controllerCount)
          : ControllerChoice.tracked(requested: held.length, padIds: held),
      current: current,
    );
    if (f.isErr) return Err(f.failureOrNull!);
    return groups.switchAssignment(
      SwitchAssignmentCommand(
        groupId: groupId,
        playerNumber: current.playerNumber,
        at: at ?? clock.now(),
        resourceId: current.resourceId,
        resourceName: name,
        activityCode: current.activityCode,
        gameId: gameId,
        controllerCount: current.controllerCount,
        controllerIds: held.isEmpty ? null : held,
      ),
    );
  }

  /// Changes one player's controllers from [at] on (new assignment at that
  /// instant; the group's shared timer is untouched).
  Future<Result<GroupAssignment>> changeControllers({
    required String groupId,
    required GroupAssignment current,
    ControllerChoice? controllers,
    int? controllerCount,
    List<String>? controllerIds,
    DateTime? at,
  }) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    final choice = resolveControllerChoice(
      controllers,
      controllerCount,
      controllerIds,
    );
    final name = await _resourceName(current.resourceId);
    final group = await _group(groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    final f = await previewAssignment(
      group: group,
      playerNumber: current.playerNumber,
      resourceId: current.resourceId,
      resourceName: name,
      activityCode: current.activityCode,
      gameId: current.gameId,
      controllers: choice,
      current: current,
    );
    if (f.isErr) return Err(f.failureOrNull!);
    return groups.switchAssignment(
      SwitchAssignmentCommand(
        groupId: groupId,
        playerNumber: current.playerNumber,
        at: at ?? clock.now(),
        resourceId: current.resourceId,
        resourceName: name,
        activityCode: current.activityCode,
        gameId: current.gameId,
        controllerCount: choice.count,
        controllerIds: choice.padIdsOrNull,
        borrowControllerIds: choice.borrowIdsOrNull,
      ),
    );
  }

  Future<Result<GroupAssignment>> addPlayer({
    required String groupId,
    required int playerNumber,
    String? playerLabel,
    required String resourceId,
    required String resourceName,
    required String activityCode,
    String? gameId,
    ControllerChoice? controllers,
    int? controllerCount,
    List<String>? controllerIds,
    DateTime? at,
  }) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    final choice = resolveControllerChoice(
      controllers,
      controllerCount,
      controllerIds,
    );
    final group = await _group(groupId);
    if (group == null) {
      return const Err(Failure(message: 'Group not found.', code: 'not_found'));
    }
    final f = await previewAssignment(
      group: group,
      playerNumber: playerNumber,
      resourceId: resourceId,
      resourceName: resourceName,
      activityCode: activityCode,
      gameId: gameId,
      controllers: choice,
    );
    if (f.isErr) return Err(f.failureOrNull!);
    return groups.addAssignment(
      AddAssignmentCommand(
        groupId: groupId,
        at: at ?? clock.now(),
        playerNumber: playerNumber,
        playerLabel: playerLabel,
        resourceId: resourceId,
        resourceName: resourceName,
        activityCode: activityCode,
        gameId: gameId,
        controllerCount: choice.count,
        controllerIds: choice.padIdsOrNull,
        borrowControllerIds: choice.borrowIdsOrNull,
      ),
    );
  }

  Future<Result<void>> endPlayer({
    required String groupId,
    required int playerNumber,
    DateTime? at,
  }) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    return groups.endAssignment(
      EndAssignmentCommand(
        groupId: groupId,
        playerNumber: playerNumber,
        at: at ?? clock.now(),
      ),
    );
  }

  // --- extend / end ----------------------------------------------------------

  /// Plans an extension of the whole group (group feature §8). Validates every
  /// system the group currently occupies against bookings and other occupancy.
  Future<Result<GroupExtensionPlan>> previewExtension(
    ActiveGroupSession g,
    int addedMinutes,
  ) async {
    final group = g.group;
    final snapshot = group.snapshot;
    final closeAt = _closeAt(group.startedAt, snapshot.calendar);
    final singleOcc = await _singleOccupancies(
      UtcInterval(group.scheduledEndAt, closeAt),
    );
    final otherGroups = await _openGroupAssignments(excludeGroupId: group.id);
    final occupancies = <Occupancy>[
      ...singleOcc,
      for (final a in otherGroups)
        Occupancy(
          resourceId: a.resourceId,
          interval: UtcInterval(a.startedAt, group.scheduledEndAt),
          isBooking: false,
          label: 'group',
        ),
    ];

    DateTime? newEnd;
    for (final resourceId in g.occupiedResourceIds) {
      final canExtend = availability.canExtend(
        resourceId: resourceId,
        currentEnd: group.scheduledEndAt,
        addedMinutes: addedMinutes,
        occupancies: occupancies,
        closeAt: closeAt,
        allowPastClose: snapshot.policy.allowExtendPastClose,
      );
      if (canExtend.isErr) return Err(canExtend.failureOrNull!);
      newEnd = canExtend.valueOrNull!;
    }
    newEnd ??= group.scheduledEndAt.add(Duration(minutes: addedMinutes));

    final before = billing.bill(
      snapshot: snapshot,
      assignments: g.assignments,
      mode: group.billingMode,
      purchasedControllerCount: group.purchasedControllerCount,
      groupStart: group.startedAt,
      openEndAt: group.scheduledEndAt,
    );
    final after = billing.bill(
      snapshot: snapshot,
      assignments: g.assignments,
      mode: group.billingMode,
      purchasedControllerCount: group.purchasedControllerCount,
      groupStart: group.startedAt,
      openEndAt: newEnd,
    );
    return Ok(
      GroupExtensionPlan(
        oldEnd: group.scheduledEndAt,
        newEnd: newEnd,
        addedMinutes: addedMinutes,
        addedCost: Paise(after.subtotal.value - before.subtotal.value),
      ),
    );
  }

  Future<Result<GroupSession>> extend(
    ActiveGroupSession g,
    int addedMinutes,
  ) async {
    final denied = guard.check(Permission.start);
    if (denied != null) return Err(denied);
    final plan = await previewExtension(g, addedMinutes);
    if (plan.isErr) return Err(plan.failureOrNull!);
    final p = plan.valueOrNull!;
    final res = await groups.extend(
      ExtendGroupCommand(
        groupId: g.group.id,
        addedMinutes: addedMinutes,
        newEndAt: p.newEnd,
        addedAmountPaise: p.addedCost.value,
      ),
    );
    if (res.isOk) {
      unawaited(reminders?.scheduleForGroup(res.valueOrNull!));
    }
    return res;
  }

  /// The final bill from all assignments, for the End screen (group feature §9).
  GroupBill endSummary(ActiveGroupSession g, {DateTime? at}) => billing.bill(
    snapshot: g.group.snapshot,
    assignments: g.assignments,
    mode: g.group.billingMode,
    purchasedControllerCount: g.group.purchasedControllerCount,
    groupStart: g.group.startedAt,
    openEndAt: at ?? clock.now(),
  );

  Future<Result<GroupSession>> end(
    ActiveGroupSession g, {
    bool markWaived = false,
    DateTime? at,
  }) async {
    final denied =
        guard.check(Permission.bill) ??
        (markWaived ? guard.check(Permission.discount) : null);
    if (denied != null) return Err(denied);
    final actualEnd = at ?? clock.now();
    if (actualEnd.isBefore(g.group.startedAt)) {
      AppTelemetry.reportTimerAnomaly(
        sessionId: g.group.id,
        anomaly: 'actualEndedAt precedes startedAt',
        resourceId: g.openAssignments.firstOrNull?.resourceId ?? 'group',
        startedAt: g.group.startedAt,
        actualEndedAt: actualEnd,
      );
    }
    final bill = endSummary(g, at: actualEnd);
    final res = await groups.end(
      EndGroupCommand(
        groupId: g.group.id,
        actualEndedAt: actualEnd,
        charges: bill.charges,
        billedAmountPaise: bill.total.value,
        markWaived: markWaived,
      ),
    );
    if (res.isOk) {
      unawaited(reminders?.cancelFor(g.group.id));
      AppTelemetry.timerStopped(
        sessionId: g.group.id,
        resourceId: g.openAssignments.firstOrNull?.resourceId ?? 'group',
        billedAmountPaise: bill.total.value,
        playedDuration: actualEnd.difference(g.group.startedAt),
        isGroup: true,
      );
      AppTelemetry.billingCalculated(
        sessionId: g.group.id,
        totalPaise: bill.total.value,
        segmentCount: g.assignments.length,
        totalSeconds: actualEnd.difference(g.group.startedAt).inSeconds,
      );
    }
    return res;
  }

  Future<Result> recordPayment(RecordGroupPaymentCommand cmd) async {
    final denied =
        guard.check(Permission.bill) ??
        (cmd.isRefund ? guard.check(Permission.discount) : null);
    if (denied != null) return Err(denied);
    final res = await groups.recordPayment(cmd);
    if (res.isOk) {
      AppTelemetry.addBreadcrumb(
        category: 'billing',
        message: 'group_payment_recorded',
        data: {
          'groupId': cmd.groupId,
          'amountPaise': cmd.amountPaise,
          'method': cmd.method.name,
          'isRefund': cmd.isRefund,
        },
      );
    }
    return res;
  }
}

final groupSessionActionsProvider = Provider<GroupSessionActions>(
  (ref) => GroupSessionActions(
    groups: ref.watch(groupSessionRepositoryProvider),
    bookings: ref.watch(bookingRepositoryProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
    sessions: ref.watch(sessionRepositoryProvider),
    catalog: ref.watch(catalogRepositoryProvider),
    clock: ref.watch(clockProvider),
    reminders: ref.watch(sessionRemindersProvider),
    pads: ref.watch(controllerAllocationRepositoryProvider),
  ),
);
