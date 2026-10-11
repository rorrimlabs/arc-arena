import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifications centre — the booking reminders the device will fire (spec §23).
///
/// Reminders are scheduled on the device, so they appear and fire even offline.
/// This screen is a plain readout of what is coming; scheduling/cancelling is
/// handled automatically when bookings are created, checked in or cancelled.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const String path = '/notifications';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final lead = ReminderPolicy.defaults.leadMinutes;

    final all = ref.watch(upcomingBookingsProvider).value ?? const <Booking>[];
    final upcoming = all
        .where((b) =>
            b.status == BookingStatus.booked &&
            b.scheduledStart.toUtc().isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    final games = {
      for (final g in ref.watch(allGamesProvider).value ?? []) g.id: g.name,
    };
    final resources = {
      for (final r in ref.watch(resourcesProvider).value ?? []) r.id: r.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5, AppSpacing.sm, AppSpacing.x5, AppSpacing.xxl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: arena.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: arena.border),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: arena.primary, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Booking reminders fire on this device $lead minutes before '
                    'each booking — even offline.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const ArenaSectionLabel(label: 'Upcoming reminders'),
          if (upcoming.isEmpty)
            _EmptyReminders(onNew: () => _openBookings(context))
          else
            for (final b in upcoming)
              _ReminderTile(
                booking: b,
                lead: lead,
                now: now,
                gameName: b.gameId == null ? null : games[b.gameId],
                resourceName:
                    b.resourceId == null ? null : resources[b.resourceId],
              ),
        ],
      ),
    );
  }

  void _openBookings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BookingScreen()));
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({
    required this.booking,
    required this.lead,
    required this.now,
    this.gameName,
    this.resourceName,
  });

  final Booking booking;
  final int lead;
  final DateTime now;
  final String? gameName;
  final String? resourceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    // Resolve by id so an older customer (not in the recent list) still shows.
    final customerName =
        ref.watch(customerByIdProvider(booking.customerId ?? '')).value?.name ??
            'Guest';
    final fireAt = booking.scheduledStart.subtract(Duration(minutes: lead));
    // The lead reminder only fires if its time is still ahead; a booking that's
    // closer than the lead window is "starting soon", not a past reminder.
    final leadPending = fireAt.isAfter(now);
    final detail = [
      if (gameName != null && gameName!.isNotEmpty) gameName!,
      resourceName ?? 'Any system',
      'at ${IstTime.format12(booking.scheduledStart)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: arena.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(Icons.alarm_outlined, color: arena.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.label.copyWith(color: arena.text)),
                const SizedBox(height: 2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(leadPending ? 'Reminds' : 'Starting',
                  style: ArenaType.micro.copyWith(color: arena.textSubtle)),
              Text(
                leadPending
                    ? IstTime.format12(fireAt)
                    : IstTime.format12(booking.scheduledStart),
                style: AppTextStyles.mono(ArenaType.label)
                    .copyWith(color: arena.text),
              ),
              Text(
                  leadPending
                      ? '${formatMinutesLabel(Duration(minutes: lead))} before'
                      : 'soon',
                  style: ArenaType.micro.copyWith(color: arena.textSubtle)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        children: [
          Icon(Icons.notifications_none_rounded,
              color: arena.textSubtle, size: 32),
          const SizedBox(height: AppSpacing.md),
          Text('No upcoming reminders',
              style: ArenaType.h3.copyWith(color: arena.text, fontSize: 16)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add a booking and you\'ll be reminded before it starts.',
            textAlign: TextAlign.center,
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('New booking'),
          ),
        ],
      ),
    );
  }
}
