/// Semantic design tokens, exposed as a [ThemeExtension].
///
/// Mirrors the SEMANTIC layer of the 404 Arena design tokens (the
/// `[data-theme="dark"]` / `[data-theme="light"]` blocks). Screens read these
/// via `context.arena` — never the raw palette directly — so a single theme
/// switch re-colours the whole app.
library;

import 'package:flutter/material.dart';

import 'arena_palette.dart';

@immutable
class ArenaColors extends ThemeExtension<ArenaColors> {
  const ArenaColors({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.overlay,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.textInverse,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryHi,
    required this.onPrimary,
    required this.primarySoft,
    required this.primaryText,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.onDanger,
    required this.info,
    required this.infoSoft,
    required this.elev2,
    required this.elev3,
    // Live station states.
    required this.stFree,
    required this.stFreeBg,
    required this.stPlaying,
    required this.stPlayingBg,
    required this.stEnding,
    required this.stEndingBg,
    required this.stOvertime,
    required this.stOvertimeBg,
    required this.stPaused,
    required this.stPausedBg,
    required this.stOos,
    required this.stOosBg,
    // Timer ramp (safe → over).
    required this.tmSafe,
    required this.tmMid,
    required this.tmLow,
    required this.tmCritical,
    required this.tmOver,
    required this.tmOverDim,
    required this.tmTrack,
    // Age bands.
    required this.bdU18,
    required this.bdU18Bg,
    required this.bd18,
    required this.bd18Bg,
  });

  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color overlay;

  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color textInverse;

  final Color border;
  final Color borderStrong;

  final Color primary;
  final Color primaryHi;
  final Color onPrimary;
  final Color primarySoft;
  final Color primaryText;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color onDanger;
  final Color info;
  final Color infoSoft;

  final List<BoxShadow> elev2;
  final List<BoxShadow> elev3;

  final Color stFree;
  final Color stFreeBg;
  final Color stPlaying;
  final Color stPlayingBg;
  final Color stEnding;
  final Color stEndingBg;
  final Color stOvertime;
  final Color stOvertimeBg;
  final Color stPaused;
  final Color stPausedBg;
  final Color stOos;
  final Color stOosBg;

  final Color tmSafe;
  final Color tmMid;
  final Color tmLow;
  final Color tmCritical;
  final Color tmOver;
  final Color tmOverDim;
  final Color tmTrack;

  final Color bdU18;
  final Color bdU18Bg;
  final Color bd18;
  final Color bd18Bg;

  // ── SEMANTIC · dark (default) ──
  static const ArenaColors dark = ArenaColors(
    bg: Ink404.i1000,
    surface: Ink404.i900,
    surfaceRaised: Ink404.i800,
    surfaceSunken: Ink404.i950,
    overlay: Color(0xBF000000),
    text: Ink404.i0,
    textMuted: Ink404.i300,
    textSubtle: Ink404.i400,
    textInverse: Ink404.i1000,
    border: Ink404.i800,
    borderStrong: Ink404.i600,
    primary: Lime404.l500,
    primaryHi: Lime404.l400,
    onPrimary: Color(0xFF000000),
    primarySoft: Color(0x1F98E748),
    primaryText: Lime404.l500,
    success: Lime404.l500,
    successSoft: Color(0x1F98E748),
    warning: Amber404.a400,
    warningSoft: Color(0x21FFB22E),
    danger: Red404.r400,
    dangerSoft: Color(0x24FF5A5A),
    onDanger: Color(0xFF000000),
    info: Ink404.i100,
    infoSoft: Color(0x14FFFFFF),
    elev2: [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
    elev3: [BoxShadow(color: Color(0xB3000000), blurRadius: 40, offset: Offset(0, -12))],
    stFree: Ink404.i300,
    stFreeBg: Ink404.i900,
    stPlaying: Lime404.l500,
    stPlayingBg: Ink404.i900,
    stEnding: Amber404.a400,
    stEndingBg: Ink404.i900,
    stOvertime: Red404.r400,
    stOvertimeBg: Color(0x14FF5A5A),
    stPaused: Ink404.i100,
    stPausedBg: Ink404.i900,
    stOos: Ink404.i500,
    stOosBg: Ink404.i950,
    tmSafe: Lime404.l500,
    tmMid: Lime404.l300,
    tmLow: Amber404.a400,
    tmCritical: Red404.r400,
    tmOver: Red404.r400,
    tmOverDim: Color(0x33FF5A5A),
    tmTrack: Ink404.i800,
    bdU18: Amber404.a400,
    bdU18Bg: Color(0x21FFB22E),
    bd18: Red404.r400,
    bd18Bg: Color(0x24FF5A5A),
  );

  // ── SEMANTIC · light ──
  static const ArenaColors light = ArenaColors(
    bg: Ink404.i0,
    surface: Ink404.i50,
    surfaceRaised: Ink404.i0,
    surfaceSunken: Ink404.i100,
    overlay: Color(0x73000000),
    text: Ink404.i1000,
    textMuted: Color(0xFF555555),
    textSubtle: Ink404.i400,
    textInverse: Ink404.i0,
    border: Ink404.i100,
    borderStrong: Ink404.i200,
    primary: Lime404.l500,
    primaryHi: Lime404.l400,
    onPrimary: Color(0xFF000000),
    primarySoft: Color(0x3898E748),
    primaryText: Lime404.l700,
    success: Lime404.l700,
    successSoft: Color(0x3898E748),
    warning: Amber404.a600,
    warningSoft: Color(0x29FFB22E),
    danger: Red404.r600,
    dangerSoft: Color(0x17CC1F1F),
    onDanger: Color(0xFFFFFFFF),
    info: Ink404.i1000,
    infoSoft: Color(0x0F000000),
    elev2: [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 6))],
    elev3: [BoxShadow(color: Color(0x29000000), blurRadius: 36, offset: Offset(0, -10))],
    stFree: Color(0xFF555555),
    stFreeBg: Ink404.i50,
    stPlaying: Lime404.l600,
    stPlayingBg: Ink404.i50,
    stEnding: Amber404.a600,
    stEndingBg: Ink404.i50,
    stOvertime: Red404.r600,
    stOvertimeBg: Color(0x0FCC1F1F),
    stPaused: Ink404.i1000,
    stPausedBg: Ink404.i50,
    stOos: Ink404.i400,
    stOosBg: Ink404.i100,
    tmSafe: Lime404.l500,
    tmMid: Lime404.l400,
    tmLow: Amber404.a400,
    tmCritical: Red404.r600,
    tmOver: Red404.r600,
    tmOverDim: Color(0x26CC1F1F),
    tmTrack: Ink404.i100,
    bdU18: Amber404.a700,
    bdU18Bg: Color(0x38FFB22E),
    bd18: Red404.r700,
    bd18Bg: Color(0x1ACC1F1F),
  );

  @override
  ArenaColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? overlay,
    Color? text,
    Color? textMuted,
    Color? textSubtle,
    Color? textInverse,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryHi,
    Color? onPrimary,
    Color? primarySoft,
    Color? primaryText,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? onDanger,
    Color? info,
    Color? infoSoft,
    List<BoxShadow>? elev2,
    List<BoxShadow>? elev3,
    Color? stFree,
    Color? stFreeBg,
    Color? stPlaying,
    Color? stPlayingBg,
    Color? stEnding,
    Color? stEndingBg,
    Color? stOvertime,
    Color? stOvertimeBg,
    Color? stPaused,
    Color? stPausedBg,
    Color? stOos,
    Color? stOosBg,
    Color? tmSafe,
    Color? tmMid,
    Color? tmLow,
    Color? tmCritical,
    Color? tmOver,
    Color? tmOverDim,
    Color? tmTrack,
    Color? bdU18,
    Color? bdU18Bg,
    Color? bd18,
    Color? bd18Bg,
  }) {
    return ArenaColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      overlay: overlay ?? this.overlay,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      textInverse: textInverse ?? this.textInverse,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryHi: primaryHi ?? this.primaryHi,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryText: primaryText ?? this.primaryText,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      elev2: elev2 ?? this.elev2,
      elev3: elev3 ?? this.elev3,
      stFree: stFree ?? this.stFree,
      stFreeBg: stFreeBg ?? this.stFreeBg,
      stPlaying: stPlaying ?? this.stPlaying,
      stPlayingBg: stPlayingBg ?? this.stPlayingBg,
      stEnding: stEnding ?? this.stEnding,
      stEndingBg: stEndingBg ?? this.stEndingBg,
      stOvertime: stOvertime ?? this.stOvertime,
      stOvertimeBg: stOvertimeBg ?? this.stOvertimeBg,
      stPaused: stPaused ?? this.stPaused,
      stPausedBg: stPausedBg ?? this.stPausedBg,
      stOos: stOos ?? this.stOos,
      stOosBg: stOosBg ?? this.stOosBg,
      tmSafe: tmSafe ?? this.tmSafe,
      tmMid: tmMid ?? this.tmMid,
      tmLow: tmLow ?? this.tmLow,
      tmCritical: tmCritical ?? this.tmCritical,
      tmOver: tmOver ?? this.tmOver,
      tmOverDim: tmOverDim ?? this.tmOverDim,
      tmTrack: tmTrack ?? this.tmTrack,
      bdU18: bdU18 ?? this.bdU18,
      bdU18Bg: bdU18Bg ?? this.bdU18Bg,
      bd18: bd18 ?? this.bd18,
      bd18Bg: bd18Bg ?? this.bd18Bg,
    );
  }

  @override
  ArenaColors lerp(ArenaColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ArenaColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      overlay: c(overlay, other.overlay),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      textSubtle: c(textSubtle, other.textSubtle),
      textInverse: c(textInverse, other.textInverse),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      primary: c(primary, other.primary),
      primaryHi: c(primaryHi, other.primaryHi),
      onPrimary: c(onPrimary, other.onPrimary),
      primarySoft: c(primarySoft, other.primarySoft),
      primaryText: c(primaryText, other.primaryText),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      onDanger: c(onDanger, other.onDanger),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      elev2: t < 0.5 ? elev2 : other.elev2,
      elev3: t < 0.5 ? elev3 : other.elev3,
      stFree: c(stFree, other.stFree),
      stFreeBg: c(stFreeBg, other.stFreeBg),
      stPlaying: c(stPlaying, other.stPlaying),
      stPlayingBg: c(stPlayingBg, other.stPlayingBg),
      stEnding: c(stEnding, other.stEnding),
      stEndingBg: c(stEndingBg, other.stEndingBg),
      stOvertime: c(stOvertime, other.stOvertime),
      stOvertimeBg: c(stOvertimeBg, other.stOvertimeBg),
      stPaused: c(stPaused, other.stPaused),
      stPausedBg: c(stPausedBg, other.stPausedBg),
      stOos: c(stOos, other.stOos),
      stOosBg: c(stOosBg, other.stOosBg),
      tmSafe: c(tmSafe, other.tmSafe),
      tmMid: c(tmMid, other.tmMid),
      tmLow: c(tmLow, other.tmLow),
      tmCritical: c(tmCritical, other.tmCritical),
      tmOver: c(tmOver, other.tmOver),
      tmOverDim: c(tmOverDim, other.tmOverDim),
      tmTrack: c(tmTrack, other.tmTrack),
      bdU18: c(bdU18, other.bdU18),
      bdU18Bg: c(bdU18Bg, other.bdU18Bg),
      bd18: c(bd18, other.bd18),
      bd18Bg: c(bd18Bg, other.bd18Bg),
    );
  }
}

/// Ergonomic access: `context.arena.primary`.
extension ArenaColorsX on BuildContext {
  ArenaColors get arena =>
      Theme.of(this).extension<ArenaColors>() ?? ArenaColors.dark;
}
