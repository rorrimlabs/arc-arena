/// Status indicators — the dot+label and the filled tag from the design.
///
/// [StatusDotLabel] is the "● PLAYING" / "● OVER TIME" marker on station cards
/// and headers. [ArenaTag] is the small filled pill ("Voided", "Cancelled").
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusDotLabel extends StatelessWidget {
  const StatusDotLabel({
    super.key,
    required this.label,
    required this.color,
    this.dot = true,
    this.dotSize = 7,
  });

  final String label;
  final Color color;
  final bool dot;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(
          label.toUpperCase(),
          style: ArenaType.micro.copyWith(color: color, letterSpacing: 0.8),
        ),
      ],
    );
  }
}

class ArenaTag extends StatelessWidget {
  const ArenaTag({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: ArenaType.micro.copyWith(color: foreground, height: 1.0),
      ),
    );
  }
}
