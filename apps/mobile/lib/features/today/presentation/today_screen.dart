import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/router/app_nav.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_bar_chart.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/bookings/presentation/upcoming_bookings.dart';
import 'package:arena_ops/features/floor/presentation/floor_screen.dart';
import 'package:arena_ops/features/money/application/money_today.dart';
import 'package:arena_ops/features/notifications/presentation/notifications_screen.dart';
import 'package:arena_ops/features/reports/application/today_report.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// The "Today" tab — the owner's glance: date, takings, who's playing, footfall.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  static const String path = '/today';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final dateLine = DateFormat('EEEE, d MMM').format(ist).toUpperCase();
    final greeting = switch (ist.hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };

    final summary = ref.watch(todaySummaryProvider);
    final active = ref.watch(activeSessionsProvider).value ?? const [];
    final resources = ref.watch(resourcesProvider).value ?? const [];
    // Only still-booked, future bookings — matches what the Notifications
    // screen lists, so the badge count can't disagree with it.
    final bookingCount = (ref.watch(upcomingBookingsProvider).value ?? const [])
        .where((b) =>
            b.status == BookingStatus.booked &&
            b.scheduledStart.toUtc().isAfter(now))
        .length;

    void openBookings() => AppNav.to(context, const BookingScreen());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ArenaScreenHeader(
              overline: dateLine,
              title: greeting,
              titleStyle: ArenaType.h1.copyWith(fontSize: 30),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                     tooltip: 'Bookings',
                     onPressed: openBookings,
                     icon: Icon(Icons.event_available_outlined,
                         color: context.arena.text),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () =>
                        AppNav.to(context, const NotificationsScreen()),
                    icon: Badge(
                      isLabelVisible: bookingCount > 0,
                      // Lime, not the default error-red: an upcoming-booking
                      // count is informational, and 404 reserves red for alerts.
                      backgroundColor: context.arena.primary,
                      textColor: context.arena.onPrimary,
                      label: Text('$bookingCount'),
                      child: Icon(Icons.notifications_none_rounded,
                          color: context.arena.text),
                    ),
                  ),
                ],
              ),
            ),
            const ConnectionStatus(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: _TakingsCard(summary: summary),
            ),
            const SizedBox(height: AppSpacing.xl),
            ArenaSectionLabel(
              label: 'Playing now · ${active.length}/${resources.length}',
              trailing: 'Open floor',
              onTrailingTap: () => context.go(FloorScreen.path),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: _PlayingNowStrip(active: active, resources: resources),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ArenaSectionLabel(label: 'Footfall'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: _FootfallCard(summary: summary),
            ),
            const SizedBox(height: AppSpacing.xl),
            ArenaSectionLabel(
              label: 'Upcoming bookings',
              trailing: 'New',
              onTrailingTap: openBookings,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: UpcomingBookings(
                emptyState: _BookingsEmpty(onNew: openBookings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> hourLabels() {
    const shown = {10, 12, 14, 16, 18, 20, 22};
    return [
      for (var h = 9; h <= 22; h++)
        shown.contains(h) ? (h <= 12 ? '$h' : '${h - 12}') : '',
    ];
  }
}

class _TakingsCard extends ConsumerWidget {
  const _TakingsCard({required this.summary});
  final AsyncValue<TodaySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final hourly = ref.watch(todayHourlyTakingsProvider).value ?? const [];
    final window = hourly.length >= 23
        ? hourly.sublist(9, 23)
        : List<int>.filled(14, 0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Takings today',
              style: ArenaType.caption.copyWith(color: arena.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          summary.when(
            loading: () => Text('₹—',
                style: ArenaType.display.copyWith(color: arena.text)),
            error: (_, _) => Text('—',
                style: ArenaType.display.copyWith(color: arena.text)),
            data: (s) => Text(
              s.collected.display,
              style: ArenaType.display.copyWith(color: arena.text),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          summary.maybeWhen(
            data: (s) => Text(
              '${s.sessions} ${s.sessions == 1 ? 'session' : 'sessions'} today',
              style: ArenaType.caption.copyWith(color: arena.textSubtle),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.lg),
          ArenaBarChart(values: window, labels: TodayScreen.hourLabels()),
        ],
      ),
    );
  }
}

class _PlayingNowStrip extends StatelessWidget {
  const _PlayingNowStrip({required this.active, required this.resources});
  final List<ActiveSession> active;
  final List<Resource> resources;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final busyIds = {for (final a in active) a.current.resourceId};
    final free = resources.where((r) => !busyIds.contains(r.id)).length;

    Widget cell(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: ArenaType.h2.copyWith(color: arena.text)),
              const SizedBox(height: 2),
              Text(label, style: ArenaType.caption.copyWith(color: arena.textMuted)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          cell('${active.length}', 'Playing'),
          _vline(arena),
          cell('$free', 'Free'),
          _vline(arena),
          cell('${resources.length}', 'Stations'),
        ],
      ),
    );
  }

  Widget _vline(ArenaColors arena) => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        color: arena.border,
      );
}

class _FootfallCard extends StatelessWidget {
  const _FootfallCard({required this.summary});
  final AsyncValue<TodaySummary> summary;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final s = summary.value;

    Widget cell(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: ArenaType.h1.copyWith(color: arena.text)),
              const SizedBox(height: 2),
              Text(label, style: ArenaType.caption.copyWith(color: arena.textMuted)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          cell('${s?.uniqueCustomers ?? 0}', 'Visitors'),
          cell('${s?.sessions ?? 0}', 'Play sessions'),
          cell('${s?.activeNow ?? 0}', 'Playing now'),
        ],
      ),
    );
  }
}

/// Empty-state for the Today "Upcoming bookings" section — keeps the area
/// useful (and offers a booking entry point) when nothing is booked yet.
class _BookingsEmpty extends StatelessWidget {
  const _BookingsEmpty({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined, color: arena.textSubtle, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No bookings yet',
                    style: ArenaType.label.copyWith(color: arena.text)),
                const SizedBox(height: 2),
                Text('Add one and we\'ll remind you before it starts.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onNew,
            // Bounded size: the theme's default minimumSize is infinite-width,
            // which can't live in an unconstrained Row.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('New'),
          ),
        ],
      ),
    );
  }
}
