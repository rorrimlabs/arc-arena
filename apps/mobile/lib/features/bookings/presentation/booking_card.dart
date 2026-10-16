import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/confirm_dialog.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_agenda.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/bookings/presentation/check_in_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One open booking as a 404-style bordered card: who, when, what and where,
/// whether it is about to start, late or missed, with check-in and the booking
/// actions. Shared by the Bookings tab and the owner's Today list so both read
/// the same.
///
/// Resolves its customer by id (not the recent-20 list) so older customers
/// still show their name, and the activity, game and station from the catalog.
class BookingCard extends ConsumerWidget {
  const BookingCard({super.key, required this.booking, this.showDay = false});

  final Booking booking;

  /// Prefix the time with its day ("Tomorrow · 7:00 PM–8:00 PM") when it is
  /// not today — for lists that are not already grouped by day.
  final bool showDay;

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final customer = booking.customerId == null
        ? null
        : ref.watch(customerByIdProvider(booking.customerId!)).value;
    final activities = ref.watch(activitiesProvider).value;
    final games = ref.watch(allGamesProvider).value;
    final resources = ref.watch(resourcesProvider).value;

    // A walk-in reservation carries its party name; otherwise the customer's.
    final name =
        _nonEmpty(booking.partyName) ?? customer?.displayName ?? 'Guest';
    final phone = _nonEmpty(booking.phone) ?? _nonEmpty(customer?.phone);

    final day = IstDate.fromUtc(booking.scheduledStart);
    final today = IstDate.fromUtc(now);
    final when = [
      if (showDay && day != today) bookingDayLabel(day, today),
      '${IstTime.format12(booking.scheduledStart)}–'
          '${IstTime.format12(booking.scheduledEnd)}',
      formatMinutesLabel(booking.plannedDuration),
    ].join(' · ');

    // Names from the catalog; nothing is shown for one that is still loading,
    // and a station that has since been removed says so rather than its id.
    String? activity;
    if (activities != null) {
      activity =
          activities
              .where((a) => a.code == booking.activityCode)
              .firstOrNull
              ?.name ??
          booking.activityCode;
    }
    String? game;
    if (booking.gameId != null && games != null) {
      game = games.where((g) => g.id == booking.gameId).firstOrNull?.name;
    }
    String? station;
    if (booking.resourceId == null) {
      station = 'Any system';
    } else if (resources != null) {
      station =
          resources
              .where((r) => r.id == booking.resourceId)
              .firstOrNull
              ?.name ??
          'Station removed';
    }
    final players = booking.playersRequired;
    final what = [
      ?activity,
      if (game != null && game.isNotEmpty) game,
      ?station,
      if (players != null) '$players ${players == 1 ? 'player' : 'players'}',
    ].join(' · ');

    final timing = BookingTiming.of(booking, now);
    // Started without a check-in: they may be late (no-show offered); once the
    // whole slot has passed it is missed and no longer holds the station.
    final started =
        timing == BookingTiming.late || timing == BookingTiming.missed;
    final (String? timingText, Color timingColor) = switch (timing) {
      BookingTiming.missed => (
        'Missed · mark no-show or cancel it',
        arena.warning,
      ),
      BookingTiming.late => ('Late · not checked in', arena.warning),
      BookingTiming.soon => (
        'Starts in ${minutesUntilStart(booking, now)} min',
        arena.primaryText,
      ),
      BookingTiming.later => (null, arena.textMuted),
    };
    final notes = _nonEmpty(booking.notes);

    return Container(
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
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArenaType.label.copyWith(color: arena.text),
                ),
                if (phone != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textSubtle),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArenaType.caption.copyWith(color: arena.text),
                ),
                if (what.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    what,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ],
                if (notes != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textSubtle),
                  ),
                ],
                if (timingText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    timingText,
                    style: ArenaType.caption.copyWith(color: timingColor),
                  ),
                ],
                if (booking.reminderStatus != ReminderStatus.scheduled) ...[
                  const SizedBox(height: 2),
                  Text(
                    booking.reminderStatus.label,
                    style: ArenaType.caption.copyWith(color: arena.textSubtle),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (canCheckInNow(booking, now))
            FilledButton(
              onPressed: () => _checkIn(context, ref),
              // Bounded: the theme's default minimumSize is infinite-width,
              // which can't live in an unconstrained Row.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Check in'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Booking actions',
            icon: Icon(Icons.more_vert, color: arena.textMuted),
            onSelected: (v) => switch (v) {
              'edit' => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookingScreen(existing: booking),
                ),
              ),
              'reminder' => _toggleReminder(context, ref),
              'cancel' => _cancel(context, ref),
              'no_show' => _noShow(context, ref),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit booking')),
              PopupMenuItem(
                value: 'reminder',
                child: Text(
                  booking.reminderStatus == ReminderStatus.scheduled
                      ? 'Turn reminder off'
                      : 'Turn reminder on',
                ),
              ),
              if (started)
                const PopupMenuItem(
                  value: 'no_show',
                  child: Text('Mark no-show'),
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

  Future<void> _toggleReminder(BuildContext context, WidgetRef ref) async {
    final on = booking.reminderStatus != ReminderStatus.scheduled;
    final toast = AppToast.of(context);
    try {
      await ref.read(bookingActionsProvider).setReminder(booking, on: on);
      toast.show(on ? 'Reminder on' : 'Reminder off');
    } catch (_) {
      toast.show('The reminder could not be changed. Try again.',
          kind: ToastKind.error);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancel this booking?',
      message: 'The slot is freed and the reminder is cleared. The booking '
          'stays in history as cancelled.',
      cancel: 'Keep it',
      confirm: 'Cancel booking',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final r = await ref.read(bookingActionsProvider).cancel(booking.id);
    if (context.mounted) {
      showResult(context, r, 'Booking cancelled');
    }
  }

  Future<void> _noShow(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Mark as no-show?',
      message: 'The customer did not come. The slot is freed and the reminder '
          'is cleared. The booking stays in history as a no-show.',
      cancel: 'Keep it',
      confirm: 'Mark no-show',
    );
    if (!confirmed || !context.mounted) return;
    final r = await ref.read(bookingActionsProvider).markNoShow(booking);
    if (context.mounted) {
      showResult(context, r, 'Marked as no-show');
    }
  }

  /// Opens the check-in sheet: the system is resolved and the physical
  /// controllers picked (and validated) before the session starts.
  Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
    final started = await showCheckInSheet(context, booking);
    if (started != true || !context.mounted) return;
    showToast(context, 'Checked in — session started');
  }
}
