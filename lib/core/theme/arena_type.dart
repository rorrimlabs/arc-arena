/// Typography — the 404 Arena type scale over three bundled families.
///
///   Saira Semi Condensed → display, timers, headings, hero numbers
///   IBM Plex Sans        → body, labels, captions
///   IBM Plex Mono        → IDs, time ranges (tabular)
///
/// Sizes/weights/line-heights are ported from the RAW · typography tokens.
library;

import 'package:flutter/material.dart';

abstract final class ArenaFonts {
  static const String display = 'Saira Semi Condensed';
  static const String body = 'IBM Plex Sans';
  static const String mono = 'IBM Plex Mono';
}

/// Tabular figures — keeps timers/amounts from jittering as digits change.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

/// The design type scale as colourless base styles. The [TextTheme] applies a
/// default colour; muted/subtle shades are applied per widget via `context.arena`.
abstract final class ArenaType {
  // Hero numbers / timers.
  static const TextStyle timer = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 64,
    height: 1.0,
    fontWeight: FontWeight.w700,
    fontFeatures: kTabular,
  );
  static const TextStyle display = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h1 = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: ArenaFonts.body,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontFamily: ArenaFonts.body,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: ArenaFonts.body,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle micro = TextStyle(
    fontFamily: ArenaFonts.body,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  /// Uppercase overline / section label (e.g. "MAIN FLOOR", "404 ARENA · …").
  static const TextStyle overline = TextStyle(
    fontFamily: ArenaFonts.display,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  /// Maps the scale onto Material's [TextTheme] slots so stock widgets inherit
  /// the right family. [onSurface] is the default text colour for the theme.
  static TextTheme textTheme(Color onSurface) {
    final t = <TextStyle>[
      display, // displayLarge
      display.copyWith(fontSize: 34), // displayMedium
      display.copyWith(fontSize: 28), // displaySmall
      h1, // headlineLarge
      h1.copyWith(fontSize: 24), // headlineMedium
      h2, // headlineSmall
      h2, // titleLarge
      h3, // titleMedium
      h3.copyWith(fontSize: 16), // titleSmall
      body, // bodyLarge
      body.copyWith(fontSize: 14), // bodyMedium
      caption, // bodySmall
      label, // labelLarge
      label.copyWith(fontSize: 12), // labelMedium
      micro.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2), // labelSmall
    ].map((s) => s.copyWith(color: onSurface)).toList();

    return TextTheme(
      displayLarge: t[0],
      displayMedium: t[1],
      displaySmall: t[2],
      headlineLarge: t[3],
      headlineMedium: t[4],
      headlineSmall: t[5],
      titleLarge: t[6],
      titleMedium: t[7],
      titleSmall: t[8],
      bodyLarge: t[9],
      bodyMedium: t[10],
      bodySmall: t[11],
      labelLarge: t[12],
      labelMedium: t[13],
      labelSmall: t[14],
    );
  }
}
