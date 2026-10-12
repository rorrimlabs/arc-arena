import 'package:flutter/material.dart';

/// Renders a controller button token (CROSS, R2, DPAD_UP …) as a readable chip
/// with the correct PlayStation glyph (spec §23). Tokens are a fixed set, so
/// unknown tokens fall back to their raw text.
class ButtonGlyph extends StatelessWidget {
  const ButtonGlyph(this.token, {super.key});
  final String token;

  static const _shapes = {
    'CROSS': ('✕', Color(0xFF5B8DEF)),
    'CIRCLE': ('○', Color(0xFFE5534B)),
    'SQUARE': ('▢', Color(0xFFD16BB7)),
    'TRIANGLE': ('△', Color(0xFF2FB49C)),
  };

  static const _dpad = {
    'DPAD_UP': '↑',
    'DPAD_DOWN': '↓',
    'DPAD_LEFT': '←',
    'DPAD_RIGHT': '→',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = _shapes[token];
    final label = shape != null
        ? shape.$1
        : (_dpad[token] ?? token.replaceAll('_', ' '));
    final color = shape?.$2 ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
