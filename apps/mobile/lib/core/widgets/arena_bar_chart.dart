/// A compact lime bar chart — the "Takings today" chart on the dashboard.
///
/// Pure presentation of pre-bucketed values; responsive (bars flex to width).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ArenaBarChart extends StatelessWidget {
  const ArenaBarChart({
    super.key,
    required this.values,
    this.labels = const [],
    this.height = 96,
  });

  /// One value per bar (already windowed to the hours you want to show).
  final List<int> values;

  /// Optional x-axis labels, aligned under the bars (same length as [values],
  /// use empty strings to skip a tick).
  final List<String> labels;

  final double height;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final maxV = values.fold<int>(0, (m, v) => v > m ? v : m);

    if (maxV == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No takings yet today',
            style: ArenaType.caption.copyWith(color: arena.textSubtle),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FractionallySizedBox(
                      alignment: Alignment.bottomCenter,
                      heightFactor: (v / maxV).clamp(v == 0 ? 0.0 : 0.04, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: v == 0 ? arena.tmTrack : arena.primary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadii.xs),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: ArenaType.micro.copyWith(
                      color: arena.textSubtle,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
