import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the "Tablet clock is wrong. Timers use server time." warning when the
/// device clock drifts more than the threshold (spec §8). Renders nothing when
/// the offset is within tolerance (always, in local-only mode).
class ClockBanner extends ConsumerWidget {
  const ClockBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(clockOffsetProvider);
    if (!offset.isSignificant) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.schedule, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offset.warning,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
