import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/floor/presentation/sheets/take_payment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sessions that have finished but whose money is not settled (brief §3, §10).
///
/// The floor is where staff notice these, so the queue lives here rather than
/// behind the Money tab — a station is free again while the bill is still open.
/// Hidden entirely when nothing is owed, so it never adds noise to a clean floor.
class AwaitingPayment extends ConsumerWidget {
  const AwaitingPayment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(awaitingPaymentProvider).value ?? const <Session>[];
    if (sessions.isEmpty) return const SizedBox.shrink();

    final owed = sessions.fold<int>(
      0,
      (sum, s) => sum + (s.billedAmountPaise ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArenaSectionLabel(
          label: 'Awaiting payment',
          trailing: '${sessions.length} · ${Paise(owed).display} billed',
        ),
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _PendingRow(session: s),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _PendingRow extends ConsumerWidget {
  const _PendingRow({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final customer = ref.watch(customerByIdProvider(session.customerId)).value;
    final payments =
        ref.watch(paymentsForSessionProvider(session.id)).value ?? const [];
    final collected = payments.fold<int>(0, (sum, p) => sum + p.amountPaise);
    final billed = session.billedAmountPaise ?? 0;
    final remaining = billed - collected;
    final partial = session.paymentStatus == PaymentStatus.partial;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.displayName ?? 'Guest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArenaType.label.copyWith(color: arena.text),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (session.actualEndedAt != null)
                      'ended ${IstTime.format12(session.actualEndedAt!)}',
                    partial
                        ? '${Paise(collected).display} paid · '
                            '${Paise(remaining).display} left'
                        : '${Paise(billed).display} unpaid',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: () => showTakePaymentSheet(context, session),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
              child: const Text('Collect'),
            ),
          ),
        ],
      ),
    );
  }
}
