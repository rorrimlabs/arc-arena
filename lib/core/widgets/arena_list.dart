/// Grouped list rows — the inset-card rows used on Reports, More and Settings.
///
/// [ArenaRowGroup] is a rounded surface card holding [ArenaListRow]s separated
/// by text-inset hairlines. Each row is an icon tile + title/subtitle + chevron.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ArenaRowGroup extends StatelessWidget {
  const ArenaRowGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, color: arena.border, indent: 72));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class ArenaListRow extends StatelessWidget {
  const ArenaListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconBackground,
    this.iconColor,
    this.chevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Optional trailing widget (replaces the chevron when set).
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconBackground;
  final Color? iconColor;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground ?? arena.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? arena.primary),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ArenaType.h3.copyWith(color: arena.text, fontSize: 17),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: ArenaType.caption.copyWith(color: arena.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (chevron)
                Icon(Icons.chevron_right, color: arena.textSubtle, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
