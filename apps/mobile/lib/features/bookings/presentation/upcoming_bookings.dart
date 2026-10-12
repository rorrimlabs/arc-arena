import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/bookings/presentation/check_in_sheet.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Upcoming bookings with one-tap check-in (spec §22). Structural area that
/// stays small until bookings exist.
///
/// [showHeader] renders the built-in section header (used on the floor).
/// [emptyState], when provided, is shown instead of collapsing when there are
/// no bookings (used on Today, which wraps this in its own section).
class UpcomingBookings extends ConsumerWidget {
  const UpcomingBookings({super.key, this.showHeader = true, this.emptyState});

  final bool showHeader;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(upcomingBookingsProvider).value ?? const [];
    final open = all.where((b) => b.status == BookingStatus.booked).toList();
    if (open.isEmpty) return emptyState ?? const SizedBox.shrink();

    final arena = context.arena;
    final games = {
      for (final g in ref.watch(allGamesProvider).value ?? []) g.id: g.name,
    };
    final resources = {
      for (final r in ref.watch(resourcesProvider).value ?? []) r.id: r.name,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Text('Upcoming bookings'.toUpperCase(),
              style: ArenaType.overline.copyWith(color: arena.text)),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final b in open)
          _BookingTile(
            booking: b,
            gameName: b.gameId == null ? null : games[b.gameId],
            resourceName: b.resourceId == null
                ? 'Any system'
                : (resources[b.resourceId] ?? b.resourceId!),
          ),
      ],
    );
  }
}

/// One upcoming booking as a 404-style bordered card. Resolves its customer by
/// id (not the recent-20 list) so older customers still show their name.
class _BookingTile extends ConsumerWidget {
  const _BookingTile({
    required this.booking,
    this.gameName,
    required this.resourceName,
  });

  final Booking booking;
  final String? gameName;
  final String resourceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final customer =
        ref.watch(customerByIdProvider(booking.customerId ?? '')).value;
    final name = customer?.displayName ?? 'Guest';
    final detail = [
      '${IstTime.format12(booking.scheduledStart)}–'
          '${IstTime.format12(booking.scheduledEnd)}',
      if (gameName != null && gameName!.isNotEmpty) gameName!,
      resourceName,
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.label.copyWith(color: arena.text)),
                const SizedBox(height: 2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
                if (booking.notes != null && booking.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(booking.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          ArenaType.caption.copyWith(color: arena.textSubtle)),
                ],
                if (booking.reminderStatus != ReminderStatus.scheduled) ...[
                  const SizedBox(height: 2),
                  Text(booking.reminderStatus.label,
                      style:
                          ArenaType.caption.copyWith(color: arena.textSubtle)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton(
            onPressed: () => _checkIn(context, ref),
            // Bounded: the theme's default minimumSize is infinite-width, which
            // can't live in an unconstrained Row.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Check in'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Booking actions',
            icon: Icon(Icons.more_vert, color: arena.textMuted),
            onSelected: (v) => switch (v) {
              'edit' => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BookingScreen(existing: booking),
                )),
              'reminder' => ref.read(bookingActionsProvider).setReminder(
                    booking,
                    on: booking.reminderStatus != ReminderStatus.scheduled,
                  ),
              'cancel' => _cancel(context, ref),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit booking')),
              PopupMenuItem(
                value: 'reminder',
                child: Text(booking.reminderStatus == ReminderStatus.scheduled
                    ? 'Turn reminder off'
                    : 'Turn reminder on'),
              ),
              const PopupMenuItem(
                value: 'cancel',
                child: Text('Cancel booking'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'The slot is freed and the reminder is cleared. The booking stays '
          'in history as cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(bookingActionsProvider).cancel(booking.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Booking cancelled')));
    }
  }

  /// Opens the check-in sheet: the system is resolved and the physical
  /// controllers picked (and validated) before the session starts.
  Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
    final started = await showCheckInSheet(context, booking);
    if (started != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked in — session started')));
  }
}
