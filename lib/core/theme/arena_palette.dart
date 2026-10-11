/// Raw design palette — the single source of truth for brand colour.
///
/// Ported verbatim from the 404 Arena design tokens (`:root` RAW layer):
/// black, white, lime #98E748, with amber + red reserved for alerts only.
/// These are *raw* values; screens should read semantic tokens from
/// [ArenaColors] (see `arena_colors.dart`) rather than reaching in here.
library;

import 'package:flutter/painting.dart';

/// Neutral ink ramp, 1000 (pure black) → 0 (pure white).
abstract final class Ink404 {
  static const Color i1000 = Color(0xFF000000);
  static const Color i950 = Color(0xFF0A0A0A);
  static const Color i900 = Color(0xFF111111);
  static const Color i850 = Color(0xFF171717);
  static const Color i800 = Color(0xFF1F1F1F);
  static const Color i700 = Color(0xFF2B2B2B);
  static const Color i600 = Color(0xFF3B3B3B);
  static const Color i500 = Color(0xFF575757);
  static const Color i400 = Color(0xFF7C7C7C);
  static const Color i300 = Color(0xFFA6A6A6);
  static const Color i200 = Color(0xFFD0D0D0);
  static const Color i100 = Color(0xFFE9E9E9);
  static const Color i50 = Color(0xFFF5F5F5);
  static const Color i0 = Color(0xFFFFFFFF);
}

/// Lime — the single accent. 500 is the brand colour.
abstract final class Lime404 {
  static const Color l300 = Color(0xFFC4F296);
  static const Color l400 = Color(0xFFAEED70);
  static const Color l500 = Color(0xFF98E748);
  static const Color l600 = Color(0xFF5E9E1E);
  static const Color l700 = Color(0xFF3D6E0C);
}

/// Amber — "ending soon" / caution only.
abstract final class Amber404 {
  static const Color a300 = Color(0xFFFFD889);
  static const Color a400 = Color(0xFFFFB22E);
  static const Color a600 = Color(0xFFA15C00);
  static const Color a700 = Color(0xFF7F4800);
}

/// Red — overtime / danger / voids only.
abstract final class Red404 {
  static const Color r300 = Color(0xFFFF9A9A);
  static const Color r400 = Color(0xFFFF5A5A);
  static const Color r600 = Color(0xFFCC1F1F);
  static const Color r700 = Color(0xFFA31414);
}

/// Corner radii (RAW · radius).
abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}
