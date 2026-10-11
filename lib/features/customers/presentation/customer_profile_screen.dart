import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/customers/application/customer_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _customerSessionsProvider =
    FutureProvider.autoDispose.family<List<Session>, String>(
  (ref, id) => ref.watch(sessionRepositoryProvider).forCustomer(id),
);

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerByIdProvider(customerId)).value;
    final stats = ref.watch(customerStatsProvider(customerId));
    final history = ref.watch(_customerSessionsProvider(customerId)).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(customer?.name ?? 'Customer')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (customer?.phone != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_outlined),
              title: Text(customer!.phone!),
            ),
          if (customer?.notes != null && customer!.notes!.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(customer.notes!),
            ),
          const SizedBox(height: AppSpacing.sm),
          stats.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('Stats unavailable: $e'),
            data: (s) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.6,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              children: [
                _StatTile('Visits', '${s.visits}'),
                _StatTile('Sessions', '${s.sessions}'),
                _StatTile('Gaming hours', s.gamingHours.toStringAsFixed(1)),
                _StatTile('Total spent', s.totalSpent.display),
                _StatTile('Avg / visit', s.averageSpend.display),
                _StatTile('Favourite', s.favouriteActivity ?? '—'),
                _StatTile('Top game', s.mostPlayedGame ?? '—'),
                _StatTile(
                  'Last visit',
                  s.lastVisit == null
                      ? '—'
                      : IstDate.fromUtc(s.lastVisit!).iso,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('History', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          if (history.isEmpty)
            const Text('No sessions yet.')
          else
            for (final s in history) _HistoryTile(session: s),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final d = IstDate.fromUtc(session.startedAt);
    final billed = session.billedAmount;
    final subtitle = [
      if (session.actualEndedAt != null)
        formatMinutesLabel(session.actualEndedAt!.difference(session.startedAt)),
      if (session.status == SessionStatus.voided) 'VOIDED',
      if (session.status == SessionStatus.active) 'ACTIVE',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: Text('${d.iso} · ${IstTime.format12(session.startedAt)}'),
      subtitle: Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(billed?.display ?? '—'),
          Text(session.paymentStatus.name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
