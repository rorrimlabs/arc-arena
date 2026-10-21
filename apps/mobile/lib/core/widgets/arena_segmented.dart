/// Segmented control — the pill toggle used across the design
/// (Owner/Staff, Bills/Log, player counts, theme switch).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ArenaSegment<T> {
  const ArenaSegment(this.value, this.label);
  final T value;
  final String label;
}

class ArenaSegmented<T> extends StatelessWidget {
  const ArenaSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 56,
  });

  final List<ArenaSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: arena.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          for (final seg in segments)
            Expanded(
              child: _Segment(
                label: seg.label,
                selected: seg.value == value,
                onTap: () => onChanged(seg.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? arena.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: selected ? Border.all(color: arena.border) : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ArenaType.label.copyWith(
            fontSize: 15,
            color: selected ? arena.text : arena.textMuted,
          ),
        ),
      ),
    );
  }
}
