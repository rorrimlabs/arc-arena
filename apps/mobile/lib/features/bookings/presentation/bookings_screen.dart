import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/router/app_nav.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/features/bookings/presentation/booking_agenda.dart';
import 'package:arena_ops/features/bookings/presentation/booking_card.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/floor/presentation/floor_screen.dart';
import 'package:arena_ops/features/floor/presentation/widgets/clock_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Bookings tab: every open reservation by the business day it starts on,
/// laid out like the floor. Missed slots come first so staff clear them (no-show
/// or cancel); then Today, Tomorrow and each later day. New bookings start from
/// the floating button.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  static const String path = '/bookings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings =
        ref.watch(upcomingBookingsProvider).value ?? const <Booking>[];
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final agenda = BookingAgenda.of(bookings, now);
    // Booking takes `start`; the actions refuse without it anyway, so the
    // button is only offered to someone who can use it.
    final canBook =
        ref.watch(authControllerProvider)?.can(Permission.start) ?? false;

    // One column on a phone; side by side on a tablet / desktop, like the
    // floor's cards.
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100
        ? 3
        : width >= 760
        ? 2
        : 1;

    return Scaffold(
      floatingActionButton: canBook
          ? FloatingActionButton.extended(
              heroTag: 'bookings_fab',
              onPressed: () => AppNav.to(context, const BookingScreen()),
              icon: const Icon(Icons.add),
              label: const Text('New Booking'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const ClockBanner(),
            ArenaScreenHeader(
              // The signed-in arena in cloud mode; the demo arena's label locally.
              overline:
                  ref.watch(cloudBindingProvider)?.arenaName ??
                  FloorScreen.demoArenaLabel,
              title: 'Bookings',
              status: _BookingsStatus(
                today: agenda.today.length,
                next: agenda.nextToday,
                missed: agenda.missed.length,
              ),
            ),
            const ConnectionStatus(),
            if (agenda.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
                child: _BookingsEmpty(canBook: canBook),
              )
            else
              for (final section in agenda.sections) ...[
                ArenaSectionLabel(
                  label: section.label,
                  trailing: section.needsAttention
                      ? '${section.bookings.length} missed'
                      : '${section.bookings.length} '
                            '${section.bookings.length == 1 ? 'booking' : 'bookings'}',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x5,
                    0,
                    AppSpacing.x5,
                    AppSpacing.xl,
                  ),
                  child: _CardRows(
                    columns: columns,
                    children: [
                      for (final b in section.bookings)
                        // Missed bookings can be from any earlier day, so
                        // their cards say which.
                        BookingCard(
                          booking: b,
                          showDay: section.needsAttention,
                        ),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// "3 today · Next at 7:30 PM" under the title, in the floor's status style.
class _BookingsStatus extends StatelessWidget {
  const _BookingsStatus({
    required this.today,
    required this.next,
    required this.missed,
  });

  final int today;
  final Booking? next;
  final int missed;

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
            color: missed > 0
                ? arena.warning
                : today > 0
                ? arena.primary
                : arena.textSubtle,
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
                  TextSpan(text: '$today '),
                  TextSpan(
                    text: 'today',
                    style: ArenaType.body.copyWith(color: arena.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              next != null
                  ? 'Next at ${IstTime.format12(next!.scheduledStart)}'
                  : 'No more today',
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cards in [columns] equal-width columns, filled row by row so the list still
/// reads in start order.
class _CardRows extends StatelessWidget {
  const _CardRows({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i += columns) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: i + c < children.length
                      ? children[i + c]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Shown when nothing is booked, so the tab never looks broken.
class _BookingsEmpty extends StatelessWidget {
  const _BookingsEmpty({required this.canBook});

  final bool canBook;

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
          Icon(
            Icons.event_available_outlined,
            color: arena.textSubtle,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No bookings yet',
                  style: ArenaType.label.copyWith(color: arena.text),
                ),
                const SizedBox(height: 2),
                Text(
                  canBook
                      ? 'Tap New Booking to reserve a station. Reservations '
                            'show here by day.'
                      : 'Reservations show here by day.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
