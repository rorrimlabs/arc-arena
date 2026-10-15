import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open bookings in start order with one-tap check-in (spec §22), as the same
/// cards the Bookings tab shows. Not grouped by day, so each card names its day
/// when it is not today.
///
/// [emptyState], when provided, is shown instead of collapsing when there are
/// no bookings (used on Today, which wraps this in its own section).
class UpcomingBookings extends ConsumerWidget {
  const UpcomingBookings({super.key, this.emptyState});

  final Widget? emptyState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(upcomingBookingsProvider).value ?? const [];
    final open = all.where((b) => b.status == BookingStatus.booked).toList();
    if (open.isEmpty) return emptyState ?? const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: BookingCard(booking: b, showDay: true),
          ),
      ],
    );
  }
}
