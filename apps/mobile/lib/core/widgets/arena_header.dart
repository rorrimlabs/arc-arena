/// Screen header + section label — the two headline patterns from the design.
///
/// [ArenaScreenHeader] is the big top-of-screen title block (overline + large
/// display title + optional status line / trailing action). [ArenaSectionLabel]
/// is the uppercase group header seen above lists and card groups
/// ("MAIN FLOOR … 3/4 in use", "PLAYING NOW · 7/11 … Open floor").
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ArenaScreenHeader extends StatelessWidget {
  const ArenaScreenHeader({
    super.key,
    this.overline,
    required this.title,
    this.titleStyle,
    this.trailing,
    this.status,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x5,
      AppSpacing.sm,
      AppSpacing.x5,
      AppSpacing.md,
    ),
  });

  /// Small uppercase line above the title (e.g. "404 ARENA · KORAMANGALA").
  final String? overline;

  /// The large display title (e.g. "Floor").
  final String title;

  /// Override the default [ArenaType.display] title style.
  final TextStyle? titleStyle;

  /// Optional trailing widget aligned to the title row (e.g. a theme toggle).
  final Widget? trailing;

  /// Optional status line under the title (e.g. the playing/ending summary).
  final Widget? status;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overline != null) ...[
            Text(
              overline!.toUpperCase(),
              style: ArenaType.overline.copyWith(color: arena.textSubtle),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: (titleStyle ?? ArenaType.display).copyWith(color: arena.text),
                ),
              ),
              ?trailing,
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpacing.md),
            status!,
          ],
        ],
      ),
    );
  }
}

class ArenaSectionLabel extends StatelessWidget {
  const ArenaSectionLabel({
    super.key,
    required this.label,
    this.trailing,
    this.onTrailingTap,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x5,
      0,
      AppSpacing.x5,
      AppSpacing.md,
    ),
  });

  final String label;
  final String? trailing;

  /// When set, [trailing] renders as a lime tappable action (e.g. "Open floor").
  final VoidCallback? onTrailingTap;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: ArenaType.overline.copyWith(color: arena.text),
            ),
          ),
          if (trailing != null)
            onTrailingTap != null
                ? GestureDetector(
                    onTap: onTrailingTap,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      trailing!,
                      style: ArenaType.label.copyWith(color: arena.primaryText),
                    ),
                  )
                : Text(
                    trailing!,
                    style: ArenaType.label
                        .copyWith(color: arena.textSubtle, fontSize: 13),
                  ),
        ],
      ),
    );
  }
}
