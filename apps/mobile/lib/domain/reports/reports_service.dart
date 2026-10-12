/// Builds the owner reports from persisted rows. PURE Dart — no Flutter, no
/// database, no clock of its own — so every figure is reproducible and
/// testable (brief §13, §15).
///
/// Source of each number:
///   * **billed** — the stored `billedAmountPaise` of sessions that *ended* in
///     the window. Never recomputed, so editing a rate tomorrow cannot change
///     a bill issued today.
///   * **collected** — payment rows timestamped in the window, refunds netted.
///   * **gaming time / utilisation / games** — session segments, clipped to the
///     window so a session spanning midnight counts on both days correctly.
///   * **revenue by activity / band** — the immutable charge rows written at
///     checkout.
library;

import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/payment.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/reports/report_models.dart';
import 'package:arena_ops/domain/value/enums.dart';

/// Everything the service needs, already fetched for the window.
class ReportInput {
  const ReportInput({
    required this.range,
    required this.sessions,
    required this.segments,
    required this.charges,
    required this.payments,
    required this.groups,
    required this.groupAssignments,
    required this.groupCharges,
    required this.groupPayments,
    required this.customers,
    required this.resources,
    required this.gameNames,
    required this.activityNames,
    required this.calendar,
  });

  final ReportRange range;
  final List<Session> sessions;
  final List<SessionSegment> segments;
  final List<SessionCharge> charges;
  final List<Payment> payments;

  final List<GroupSession> groups;
  final List<GroupAssignment> groupAssignments;
  final List<GroupCharge> groupCharges;
  final List<GroupPayment> groupPayments;

  final List<Customer> customers;
  final List<Resource> resources;
  final Map<String, String> gameNames;
  final Map<String, String> activityNames;

  /// Used to work out how many minutes the centre was open — the denominator
  /// for utilisation.
  final BusinessCalendar calendar;
}

class ReportsService {
  const ReportsService();

  ArenaReport build(ReportInput input) {
    final range = input.range;
    final start = range.startUtc;
    final end = range.endUtc;

    // --- sessions that ended in the window → billed / waived ----------------
    final endedSessions = input.sessions
        .where((s) =>
            s.status == SessionStatus.completed &&
            s.actualEndedAt != null &&
            !s.actualEndedAt!.isBefore(start) &&
            s.actualEndedAt!.isBefore(end))
        .toList();
    final endedGroups = input.groups
        .where((g) =>
            g.status == GroupSessionStatus.completed &&
            g.actualEndedAt != null &&
            !g.actualEndedAt!.isBefore(start) &&
            g.actualEndedAt!.isBefore(end))
        .toList();

    var billed = 0;
    var waived = 0;
    for (final s in endedSessions) {
      billed += s.billedAmountPaise ?? 0;
      if (s.paymentStatus == PaymentStatus.waived) {
        waived += s.billedAmountPaise ?? 0;
      }
    }
    for (final g in endedGroups) {
      billed += g.billedAmountPaise ?? 0;
      if (g.paymentStatus == PaymentStatus.waived) {
        waived += g.billedAmountPaise ?? 0;
      }
    }

    // --- payments in the window → collected ---------------------------------
    final windowPayments =
        input.payments.where((p) => _inWindow(p.createdAt, start, end)).toList();
    final windowGroupPayments = input.groupPayments
        .where((p) => _inWindow(p.createdAt, start, end))
        .toList();

    var collected = 0;
    var refunded = 0;
    final byMethodPaise = <PaymentMethod, int>{};
    final byMethodCount = <PaymentMethod, int>{};
    void countPayment(PaymentMethod m, int amount, bool isRefund) {
      collected += amount;
      if (isRefund || amount < 0) refunded += amount.abs();
      byMethodPaise[m] = (byMethodPaise[m] ?? 0) + amount;
      byMethodCount[m] = (byMethodCount[m] ?? 0) + 1;
    }

    for (final p in windowPayments) {
      countPayment(p.method, p.amountPaise, p.isRefund);
    }
    for (final p in windowGroupPayments) {
      countPayment(p.method, p.amountPaise, p.isRefund);
    }

    // --- segments clipped to the window → time, utilisation, games ----------
    final clipped = <({SessionSegment seg, int minutes})>[];
    for (final seg in input.segments) {
      final minutes = _clippedMinutes(seg.startedAt, seg.endedAt, start, end);
      if (minutes > 0) clipped.add((seg: seg, minutes: minutes));
    }
    final clippedGroup = <({GroupAssignment seg, int minutes})>[];
    for (final a in input.groupAssignments) {
      final minutes = _clippedMinutes(a.startedAt, a.endedAt, start, end);
      if (minutes > 0) clippedGroup.add((seg: a, minutes: minutes));
    }

    final gamingMinutes = clipped.fold<int>(0, (a, c) => a + c.minutes) +
        clippedGroup.fold<int>(0, (a, c) => a + c.minutes);

    // --- revenue by activity and by price band ------------------------------
    final windowCharges = input.charges
        .where((c) => _overlaps(c.segmentStart, c.segmentEnd, start, end))
        .toList();
    final windowGroupCharges = input.groupCharges
        .where((c) => _overlaps(c.segmentStart, c.segmentEnd, start, end))
        .toList();

    final byActivityPaise = <String, int>{};
    final byActivityCount = <String, int>{};
    final byBandPaise = <String, int>{};
    final byBandCount = <String, int>{};
    void countCharge(String activity, String band, int amount) {
      byActivityPaise[activity] = (byActivityPaise[activity] ?? 0) + amount;
      byActivityCount[activity] = (byActivityCount[activity] ?? 0) + 1;
      byBandPaise[band] = (byBandPaise[band] ?? 0) + amount;
      byBandCount[band] = (byBandCount[band] ?? 0) + 1;
    }

    for (final c in windowCharges) {
      countCharge(c.activityCode, c.bandCode, c.amountPaise);
    }
    for (final c in windowGroupCharges) {
      countCharge(c.activityCode, c.bandCode, c.amountPaise);
    }

    // --- per-resource utilisation -------------------------------------------
    final openMinutes = _openMinutes(range, input.calendar);
    final playedByResource = <String, int>{};
    final sessionsByResource = <String, Set<String>>{};
    for (final c in clipped) {
      playedByResource[c.seg.resourceId] =
          (playedByResource[c.seg.resourceId] ?? 0) + c.minutes;
      (sessionsByResource[c.seg.resourceId] ??= {}).add(c.seg.sessionId);
    }
    for (final c in clippedGroup) {
      playedByResource[c.seg.resourceId] =
          (playedByResource[c.seg.resourceId] ?? 0) + c.minutes;
      (sessionsByResource[c.seg.resourceId] ??= {}).add(c.seg.groupId);
    }
    final resourceUsage = [
      for (final r in input.resources)
        ResourceUsage(
          resourceId: r.id,
          resourceName: r.name,
          playedMinutes: playedByResource[r.id] ?? 0,
          // A disabled station was never open for play, so it does not drag
          // the average utilisation down.
          openMinutes: r.status == ResourceStatus.disabled ? 0 : openMinutes,
          sessions: sessionsByResource[r.id]?.length ?? 0,
        ),
    ]..sort((a, b) => b.playedMinutes.compareTo(a.playedMinutes));

    // --- most played games ---------------------------------------------------
    final playedByGame = <String, int>{};
    final sessionsByGame = <String, Set<String>>{};
    for (final c in clipped) {
      final id = c.seg.gameId;
      if (id == null) continue;
      playedByGame[id] = (playedByGame[id] ?? 0) + c.minutes;
      (sessionsByGame[id] ??= {}).add(c.seg.sessionId);
    }
    for (final c in clippedGroup) {
      final id = c.seg.gameId;
      if (id == null) continue;
      playedByGame[id] = (playedByGame[id] ?? 0) + c.minutes;
      (sessionsByGame[id] ??= {}).add(c.seg.groupId);
    }
    final topGames = [
      for (final e in playedByGame.entries)
        GamePlay(
          gameId: e.key,
          gameName: input.gameNames[e.key] ?? e.key,
          playedMinutes: e.value,
          sessions: sessionsByGame[e.key]?.length ?? 0,
        ),
    ]..sort((a, b) => b.playedMinutes.compareTo(a.playedMinutes));

    // --- per-day totals -------------------------------------------------------
    final byDay = <DayTotals>[];
    for (final day in range.days) {
      final dayStart = day.startOfDayUtc();
      final dayEnd = day.endOfDayUtc();
      var dayBilled = 0;
      var daySessions = 0;
      for (final s in endedSessions) {
        if (_inWindow(s.actualEndedAt!, dayStart, dayEnd)) {
          dayBilled += s.billedAmountPaise ?? 0;
          daySessions++;
        }
      }
      for (final g in endedGroups) {
        if (_inWindow(g.actualEndedAt!, dayStart, dayEnd)) {
          dayBilled += g.billedAmountPaise ?? 0;
          daySessions++;
        }
      }
      var dayCollected = 0;
      for (final p in windowPayments) {
        if (_inWindow(p.createdAt, dayStart, dayEnd)) dayCollected += p.amountPaise;
      }
      for (final p in windowGroupPayments) {
        if (_inWindow(p.createdAt, dayStart, dayEnd)) dayCollected += p.amountPaise;
      }
      var dayMinutes = 0;
      for (final c in input.segments) {
        dayMinutes += _clippedMinutes(c.startedAt, c.endedAt, dayStart, dayEnd);
      }
      for (final a in input.groupAssignments) {
        dayMinutes += _clippedMinutes(a.startedAt, a.endedAt, dayStart, dayEnd);
      }
      byDay.add(DayTotals(
        day: day,
        billedPaise: dayBilled,
        collectedPaise: dayCollected,
        sessions: daySessions,
        gamingMinutes: dayMinutes,
      ));
    }

    // --- customers -------------------------------------------------------------
    final customerNames = {
      for (final c in input.customers) c.id: c.displayName,
    };
    final seen = <String>{
      for (final s in endedSessions) s.customerId,
      for (final g in endedGroups) g.primaryCustomerId,
    };
    final newCustomers = input.customers
        .where((c) => seen.contains(c.id) && _inWindow(c.createdAt, start, end))
        .length;

    // --- session history --------------------------------------------------------
    final paidBySession = <String, int>{};
    for (final p in input.payments) {
      paidBySession[p.sessionId] = (paidBySession[p.sessionId] ?? 0) + p.amountPaise;
    }
    final paidByGroup = <String, int>{};
    for (final p in input.groupPayments) {
      paidByGroup[p.groupId] = (paidByGroup[p.groupId] ?? 0) + p.amountPaise;
    }
    final segmentsBySession = <String, List<SessionSegment>>{};
    for (final seg in input.segments) {
      (segmentsBySession[seg.sessionId] ??= []).add(seg);
    }
    final assignmentsByGroup = <String, List<GroupAssignment>>{};
    for (final a in input.groupAssignments) {
      (assignmentsByGroup[a.groupId] ??= []).add(a);
    }
    final resourceNames = {for (final r in input.resources) r.id: r.name};

    final history = <SessionHistoryRow>[];
    for (final s in endedSessions) {
      // Copy before sorting: the map's list is shared with the loops above,
      // and the empty fallback is unmodifiable.
      final segs = [...?segmentsBySession[s.id]]
        ..sort((a, b) => a.index.compareTo(b.index));
      history.add(_historyRow(
        id: s.id,
        name: customerNames[s.customerId] ?? 'Guest',
        startedAt: s.startedAt,
        endedAt: s.actualEndedAt,
        billed: s.billedAmountPaise ?? 0,
        collected: paidBySession[s.id] ?? 0,
        status: s.paymentStatus,
        isGroup: false,
        resourceIds: [for (final seg in segs) seg.resourceId],
        gameIds: [
          for (final seg in segs)
            if (seg.gameId != null) seg.gameId!,
        ],
        minutes: segs.fold<int>(
          0,
          (a, seg) => a + _clippedMinutes(seg.startedAt, seg.endedAt, start, end),
        ),
        resourceNames: resourceNames,
        gameNames: input.gameNames,
      ));
    }
    for (final g in endedGroups) {
      final assigned = [...?assignmentsByGroup[g.id]]
        ..sort((a, b) => a.index.compareTo(b.index));
      history.add(_historyRow(
        id: g.id,
        name: customerNames[g.primaryCustomerId] ?? 'Guest',
        startedAt: g.startedAt,
        endedAt: g.actualEndedAt,
        billed: g.billedAmountPaise ?? 0,
        collected: paidByGroup[g.id] ?? 0,
        status: g.paymentStatus,
        isGroup: true,
        resourceIds: [for (final a in assigned) a.resourceId],
        gameIds: [
          for (final a in assigned)
            if (a.gameId != null) a.gameId!,
        ],
        minutes: assigned.fold<int>(
          0,
          (acc, a) => acc + _clippedMinutes(a.startedAt, a.endedAt, start, end),
        ),
        resourceNames: resourceNames,
        gameNames: input.gameNames,
      ));
    }
    history.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    MoneyRow activityRow(String code) => MoneyRow(
          label: input.activityNames[code] ?? code,
          paise: byActivityPaise[code] ?? 0,
          count: byActivityCount[code] ?? 0,
        );

    return ArenaReport(
      range: range,
      billedPaise: billed,
      collectedPaise: collected,
      waivedPaise: waived,
      refundedPaise: refunded,
      sessionCount: endedSessions.length + endedGroups.length,
      gamingMinutes: gamingMinutes,
      uniqueCustomers: seen.length,
      newCustomers: newCustomers,
      byActivity: [
        for (final code in byActivityPaise.keys) activityRow(code),
      ]..sort((a, b) => b.paise.compareTo(a.paise)),
      byMethod: [
        // Every method is listed, including those with no takings, so the
        // breakdown has a stable shape day to day.
        for (final m in PaymentMethod.values)
          MoneyRow(
            label: _methodLabel(m),
            paise: byMethodPaise[m] ?? 0,
            count: byMethodCount[m] ?? 0,
          ),
      ],
      byBand: [
        for (final b in Band.values)
          MoneyRow(
            label: b == Band.happy ? 'Happy hour' : 'Standard',
            paise: byBandPaise[b.code] ?? 0,
            count: byBandCount[b.code] ?? 0,
          ),
      ],
      byDay: byDay,
      resourceUsage: resourceUsage,
      topGames: topGames,
      history: history,
    );
  }

  SessionHistoryRow _historyRow({
    required String id,
    required String name,
    required DateTime startedAt,
    required DateTime? endedAt,
    required int billed,
    required int collected,
    required PaymentStatus status,
    required bool isGroup,
    required List<String> resourceIds,
    required List<String> gameIds,
    required int minutes,
    required Map<String, String> resourceNames,
    required Map<String, String> gameNames,
  }) {
    // Distinct, order-preserving: a session that moved HEX → VOID → HEX reads
    // "HEX, VOID" rather than repeating.
    List<String> distinct(List<String> ids, Map<String, String> names) {
      final out = <String>[];
      for (final i in ids) {
        final label = names[i] ?? i;
        if (!out.contains(label)) out.add(label);
      }
      return out;
    }

    return SessionHistoryRow(
      sessionId: id,
      customerName: name,
      startedAt: startedAt,
      endedAt: endedAt,
      resources: distinct(resourceIds, resourceNames),
      games: distinct(gameIds, gameNames),
      playedMinutes: minutes,
      billedPaise: billed,
      collectedPaise: collected,
      paymentStatus: status,
      isGroup: isGroup,
    );
  }

  /// Minutes the centre was scheduled to be open across the whole window.
  int _openMinutes(ReportRange range, BusinessCalendar calendar) {
    var total = 0;
    for (final day in range.days) {
      final w = calendar.operatingWindow(day);
      if (w != null) total += w.duration.inMinutes;
    }
    return total;
  }

  /// Whole minutes of [start, end) that fall inside the window. An unfinished
  /// segment is counted only up to the window's end, never into the future.
  int _clippedMinutes(
    DateTime segStart,
    DateTime? segEnd,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final from = segStart.isAfter(windowStart) ? segStart : windowStart;
    final rawEnd = segEnd ?? windowEnd;
    final to = rawEnd.isBefore(windowEnd) ? rawEnd : windowEnd;
    if (!to.isAfter(from)) return 0;
    return to.difference(from).inMinutes;
  }

  bool _inWindow(DateTime t, DateTime start, DateTime end) =>
      !t.isBefore(start) && t.isBefore(end);

  bool _overlaps(DateTime s, DateTime e, DateTime start, DateTime end) =>
      s.isBefore(end) && e.isAfter(start);

  String _methodLabel(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}
