import 'package:arena_ops/core/widgets/connection_status.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/arena_segmented.dart';
import 'package:arena_ops/features/money/application/money_today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _MoneyTab { bills, log }

/// The "Money" tab — today's takings by method (Bills) and the payment log.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  static const String path = '/money';

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  _MoneyTab _tab = _MoneyTab.bills;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final payments = ref.watch(todayPaymentsProvider).value ?? const <MoneyEntry>[];
    final total = payments.fold<int>(0, (a, p) => a + p.amountPaise);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ArenaScreenHeader(
              title: 'Money',
              status: Text(
                '${payments.length} ${payments.length == 1 ? 'payment' : 'payments'} today · ${Paise(total).display}',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
            ),
            // Totals include payments this device has not sent yet; the strip
            // says so (cloud mode) instead of implying the server has them.
            const ConnectionStatus(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
              child: ArenaSegmented<_MoneyTab>(
                value: _tab,
                onChanged: (t) => setState(() => _tab = t),
                segments: const [
                  ArenaSegment(_MoneyTab.bills, 'Bills'),
                  ArenaSegment(_MoneyTab.log, 'Log'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_tab == _MoneyTab.bills)
              const _MethodGrid()
            else
              _PaymentLog(payments: payments),
          ],
        ),
      ),
    );
  }
}

class _MethodGrid extends ConsumerWidget {
  const _MethodGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown =
        ref.watch(todayMethodBreakdownProvider).value ?? const <MethodBreakdown>[];
    if (breakdown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.45,
        children: [for (final b in breakdown) _MethodCard(b: b)],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.b});
  final MethodBreakdown b;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(b.method.label,
              style: ArenaType.caption.copyWith(color: arena.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          Text(Paise(b.totalPaise).display,
              style: ArenaType.h1.copyWith(color: arena.text)),
          const SizedBox(height: AppSpacing.xs),
          Text('${b.count} ${b.count == 1 ? 'bill' : 'bills'}',
              style: ArenaType.caption.copyWith(color: arena.textSubtle)),
        ],
      ),
    );
  }
}

class _PaymentLog extends StatelessWidget {
  const _PaymentLog({required this.payments});
  final List<MoneyEntry> payments;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    if (payments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text('No payments recorded yet today.',
              style: ArenaType.body.copyWith(color: arena.textMuted)),
        ),
      );
    }
    return Column(
      children: [
        for (final p in payments) _PaymentRow(payment: p),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final MoneyEntry payment;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final ist = payment.createdAt
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    final time = DateFormat('HH:mm').format(ist);
    final refund = payment.isRefund;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x5, vertical: AppSpacing.md),
      child: Row(
        children: [
          Text(time,
              style: AppTextStyles.mono(ArenaType.body)
                  .copyWith(color: arena.textMuted, fontSize: 14)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              refund ? '${payment.method.label} · refund' : payment.method.label,
              style: ArenaType.label.copyWith(color: arena.text),
            ),
          ),
          Text(
            Paise(payment.amountPaise).display,
            style: AppTextStyles.amount(context)
                .copyWith(fontSize: 18, color: refund ? arena.danger : arena.text),
          ),
        ],
      ),
    );
  }
}
