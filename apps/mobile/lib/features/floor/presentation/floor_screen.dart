import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/bookings/presentation/upcoming_bookings.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/extend_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/session_actions_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/view_games_sheet.dart';
import 'package:arena_ops/features/floor/presentation/widgets/awaiting_payment.dart';
import 'package:arena_ops/features/floor/presentation/station_detail_screen.dart';
import 'package:arena_ops/features/floor/presentation/widgets/clock_banner.dart';
import 'package:arena_ops/features/floor/presentation/widgets/station_card.dart';
import 'package:arena_ops/features/group_sessions/presentation/group_detail_screen.dart';
import 'package:arena_ops/features/group_sessions/presentation/group_session_screen.dart';
import 'package:arena_ops/features/new_session/presentation/new_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The floor — the most important screen. Zone-grouped station cards (design).
/// Responsive: 2 columns on a phone, more on a wide tablet.
class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key});

  static const String path = '/floor';

  void _newSession(BuildContext context, {Resource? resource}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewSessionScreen(initialResource: resource),
      ),
    );
  }

  void _newGroup(BuildContext context, {Resource? resource}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupSessionScreen(initialResource: resource),
      ),
    );
  }

  void _showNewMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Single session'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _newSession(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Group session'),
              subtitle: const Text('Several players / systems, one timer'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _newGroup(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final active =
        ref.watch(activeSessionsProvider).value ?? const <ActiveSession>[];
    final activeGroups =
        ref.watch(activeGroupsProvider).value ?? const <ActiveGroupSession>[];
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();

    // Map each resource to the session currently playing on it.
    final byResource = <String, ActiveSession>{
      for (final a in active) a.current.resourceId: a,
    };

    // The soonest upcoming booking per resource, so a free card can show
    // "Reserved" instead of inviting staff to start a session into it.
    final bookings =
        ref.watch(upcomingBookingsProvider).value ?? const <Booking>[];
    final nextBookingByResource = <String, Booking>{};
    for (final b in bookings) {
      if (b.resourceId == null || !b.isOpen) continue;
      final existing = nextBookingByResource[b.resourceId!];
      if (existing == null ||
          b.scheduledStart.isBefore(existing.scheduledStart)) {
        nextBookingByResource[b.resourceId!] = b;
      }
    }

    // Map each resource a group is using to that group + the open assignment.
    final groupByResource =
        <String, ({ActiveGroupSession group, GroupAssignment seg})>{
          for (final g in activeGroups)
            for (final seg in g.openAssignments)
              seg.resourceId: (group: g, seg: seg),
        };

    final warn = ref.watch(warnThresholdProvider);
    var endingSoon = 0;
    for (final a in active) {
      final st = SessionTimer(
        startedAt: a.session.startedAt,
        scheduledEndAt: a.session.scheduledEndAt,
        warnThreshold: warn,
      ).state(now);
      if (st != SessionVisualState.normal) endingSoon++;
    }
    for (final g in activeGroups) {
      final st = SessionTimer(
        startedAt: g.group.startedAt,
        scheduledEndAt: g.group.scheduledEndAt,
        warnThreshold: warn,
      ).state(now);
      if (st != SessionVisualState.normal) endingSoon++;
    }

    // Two-column card grid like the design; more on tablet / desktop. A card
    // now carries who / game / controllers / start / due / bill, so a narrow
    // phone gets a single full-width column rather than squeezing all of it
    // into ~170 px.
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100
        ? 4
        : width >= 760
        ? 3
        : width >= 540
        ? 2
        : 1;

    final zones = <ResourceKind, List<Resource>>{};
    for (final r in resources) {
      (zones[r.kind] ??= []).add(r);
    }
    const kindLabel = {
      ResourceKind.station: 'Stations',
      ResourceKind.table: 'Tables',
      ResourceKind.room: 'Rooms',
    };
    const kindOrder = [
      ResourceKind.station,
      ResourceKind.table,
      ResourceKind.room,
    ];

    Widget cardFor(Resource r) {
      final a = byResource[r.id];
      final grp = groupByResource[r.id];
      if (a == null && grp != null) {
        return StationCard(
          resource: r,
          group: grp.group,
          groupAssignment: grp.seg,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: grp.group.group.id),
            ),
          ),
        );
      }
      return StationCard(
        resource: r,
        active: a,
        nextBooking: nextBookingByResource[r.id],
        onStart: a == null ? () => _newSession(context, resource: r) : null,
        onViewGames:
            a == null && r.kind == ResourceKind.station && r.status.isBookable
            ? () => showViewGamesSheet(context, r)
            : null,
        onTap: a == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StationDetailScreen(sessionId: a.session.id),
                ),
              ),
        onExtend: a == null ? null : () => showExtendSheet(context, a),
        onBill: a == null ? null : () => showEndSessionSheet(context, a),
        onMore: a == null ? null : () => showSessionActionsSheet(context, a),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewMenu(context),
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const ClockBanner(),
            ArenaScreenHeader(
              overline: '404 Arena · Koratty',
              title: 'Floor',
              trailing: IconButton(
                tooltip: 'Bookings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookingScreen()),
                ),
                icon: Icon(Icons.event_available_outlined, color: arena.text),
              ),
              status: _FloorStatus(
                playing: {...byResource.keys, ...groupByResource.keys}.length,
                total: resources.length,
                endingSoon: endingSoon,
              ),
            ),
            const ConnectionStatus(),
            for (final kind in kindOrder)
              if ((zones[kind] ?? const []).isNotEmpty) ...[
                Builder(
                  builder: (context) {
                    final list = zones[kind]!;
                    final inUse = list
                        .where(
                          (r) =>
                              byResource.containsKey(r.id) ||
                              groupByResource.containsKey(r.id),
                        )
                        .length;
                    return ArenaSectionLabel(
                      label: kindLabel[kind]!,
                      trailing: '$inUse/${list.length} in use',
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x5,
                    0,
                    AppSpacing.x5,
                    AppSpacing.xl,
                  ),
                  child: _Masonry(
                    // A zone never uses more columns than it has cards, so a
                    // lone table/room goes full-width instead of leaving a hole.
                    columns: zones[kind]!.length < columns
                        ? zones[kind]!.length
                        : columns,
                    children: [for (final r in zones[kind]!) cardFor(r)],
                  ),
                ),
              ],
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: AwaitingPayment(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: UpcomingBookings(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorStatus extends StatelessWidget {
  const _FloorStatus({
    required this.playing,
    required this.total,
    required this.endingSoon,
  });

  final int playing;
  final int total;
  final int endingSoon;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6, right: AppSpacing.md),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: playing > 0 ? arena.primary : arena.textSubtle,
            shape: BoxShape.circle,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: ArenaType.h3.copyWith(color: arena.text, fontSize: 17),
                children: [
                  TextSpan(text: '$playing/$total '),
                  TextSpan(
                    text: 'playing',
                    style: ArenaType.body.copyWith(color: arena.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              endingSoon > 0 ? '$endingSoon ending soon' : 'All comfortable',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Simple responsive masonry: round-robins children into [columns] columns so
/// cards keep their natural (varying) heights, like the design.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(columns, (_) => <Widget>[]);
    for (var i = 0; i < children.length; i++) {
      cols[i % columns].add(children[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < cols[c].length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  cols[c][i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
