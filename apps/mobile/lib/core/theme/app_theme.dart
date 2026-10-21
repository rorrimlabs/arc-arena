/// App theme — the 404 Arena design system in Material 3.
///
/// Black counter-top surface, lime accent, amber/red for alerts only. Big
/// readable timers and amounts (Saira Semi Condensed), body in IBM Plex Sans,
/// IDs/times in IBM Plex Mono with tabular figures.
///
/// The design tokens live in [ArenaColors] (semantic) over [Ink404]/[Lime404]
/// (raw). This file wires them into [ThemeData] + [ColorScheme] and keeps the
/// long-standing helpers ([AppSpacing], [SessionStatusColors], [AppTextStyles])
/// so existing screens pick up the new look without churn.
library;

import 'package:flutter/material.dart';

import 'arena_colors.dart';
import 'arena_palette.dart';
import 'arena_type.dart';

export 'arena_colors.dart' show ArenaColors, ArenaColorsX;
export 'arena_palette.dart' show Ink404, Lime404, Amber404, Red404, AppRadii;
export 'arena_type.dart' show ArenaFonts, ArenaType, kTabular;

/// 4-based spacing scale (RAW · spacing).
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4; // sp-1
  static const double sm = 8; // sp-2
  static const double md = 12; // sp-3
  static const double lg = 16; // sp-4
  static const double x5 = 20; // sp-5
  static const double xl = 24; // sp-6
  static const double xxl = 32; // sp-8
  static const double x10 = 40; // sp-10
  static const double x16 = 64; // sp-16

  /// Minimum height for primary tappable controls (≥48 tap target).
  static const double minTarget = 56;
}

/// Colours for the live session states shown on the floor.
///
/// Thin adapter over [ArenaColors] station tokens so the existing
/// `context.statusColors` call sites re-colour for free.
@immutable
class SessionStatusColors extends ThemeExtension<SessionStatusColors> {
  const SessionStatusColors({
    required this.normal,
    required this.normalContainer,
    required this.warning,
    required this.warningContainer,
    required this.overtime,
    required this.overtimeContainer,
  });

  /// Comfortable remaining time (playing · lime).
  final Color normal;
  final Color normalContainer;

  /// Near the end (ending · amber).
  final Color warning;
  final Color warningContainer;

  /// Past scheduled end (overtime · red).
  final Color overtime;
  final Color overtimeContainer;

  @override
  SessionStatusColors copyWith({
    Color? normal,
    Color? normalContainer,
    Color? warning,
    Color? warningContainer,
    Color? overtime,
    Color? overtimeContainer,
  }) =>
      SessionStatusColors(
        normal: normal ?? this.normal,
        normalContainer: normalContainer ?? this.normalContainer,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
        overtime: overtime ?? this.overtime,
        overtimeContainer: overtimeContainer ?? this.overtimeContainer,
      );

  @override
  SessionStatusColors lerp(SessionStatusColors? other, double t) {
    if (other == null) return this;
    return SessionStatusColors(
      normal: Color.lerp(normal, other.normal, t)!,
      normalContainer: Color.lerp(normalContainer, other.normalContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      overtime: Color.lerp(overtime, other.overtime, t)!,
      overtimeContainer: Color.lerp(overtimeContainer, other.overtimeContainer, t)!,
    );
  }

  static const SessionStatusColors light = SessionStatusColors(
    normal: Lime404.l600,
    normalContainer: Ink404.i50,
    warning: Amber404.a600,
    warningContainer: Ink404.i50,
    overtime: Red404.r600,
    overtimeContainer: Color(0x0FCC1F1F),
  );

  static const SessionStatusColors dark = SessionStatusColors(
    normal: Lime404.l500,
    normalContainer: Ink404.i900,
    warning: Amber404.a400,
    warningContainer: Ink404.i900,
    overtime: Red404.r400,
    overtimeContainer: Color(0x14FF5A5A),
  );
}

/// Tabular-figure helpers for things that must not jitter as digits change.
class AppTextStyles {
  const AppTextStyles._();

  /// Switch any style to the mono family (IDs, time ranges) with tabular digits.
  static TextStyle mono(TextStyle base) =>
      base.copyWith(fontFamily: ArenaFonts.mono, fontFeatures: kTabular);

  /// Large display timer (Saira), tabular so it never jitters.
  static TextStyle timer(BuildContext context) => Theme.of(context)
      .textTheme
      .displaySmall!
      .copyWith(fontWeight: FontWeight.w700, fontFeatures: kTabular);

  /// Currency amounts — Saira bold, tabular.
  static TextStyle amount(BuildContext context) => Theme.of(context)
      .textTheme
      .titleLarge!
      .copyWith(fontWeight: FontWeight.w700, fontFeatures: kTabular);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() =>
      _build(Brightness.light, SessionStatusColors.light, ArenaColors.light);
  static ThemeData dark() =>
      _build(Brightness.dark, SessionStatusColors.dark, ArenaColors.dark);

  // ── ColorSchemes derived from the tokens ──
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Lime404.l500,
    onPrimary: Color(0xFF000000),
    primaryContainer: Lime404.l700,
    onPrimaryContainer: Lime404.l300,
    secondary: Lime404.l400,
    onSecondary: Color(0xFF000000),
    secondaryContainer: Ink404.i800,
    onSecondaryContainer: Ink404.i0,
    tertiary: Lime404.l300,
    onTertiary: Color(0xFF000000),
    error: Red404.r400,
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF5A1511),
    onErrorContainer: Red404.r300,
    surface: Ink404.i900,
    onSurface: Ink404.i0,
    onSurfaceVariant: Ink404.i300,
    surfaceContainerLowest: Ink404.i1000,
    surfaceContainerLow: Ink404.i950,
    surfaceContainer: Ink404.i900,
    surfaceContainerHigh: Ink404.i850,
    surfaceContainerHighest: Ink404.i800,
    surfaceDim: Ink404.i950,
    surfaceBright: Ink404.i800,
    outline: Ink404.i600,
    outlineVariant: Ink404.i800,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Ink404.i100,
    onInverseSurface: Ink404.i900,
    inversePrimary: Lime404.l700,
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Lime404.l500,
    onPrimary: Color(0xFF000000),
    primaryContainer: Lime404.l300,
    onPrimaryContainer: Lime404.l700,
    secondary: Lime404.l600,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Ink404.i100,
    onSecondaryContainer: Ink404.i1000,
    tertiary: Lime404.l700,
    onTertiary: Color(0xFFFFFFFF),
    error: Red404.r600,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFADAD7),
    onErrorContainer: Red404.r700,
    surface: Ink404.i50,
    onSurface: Ink404.i1000,
    onSurfaceVariant: Color(0xFF555555),
    surfaceContainerLowest: Ink404.i0,
    surfaceContainerLow: Ink404.i50,
    surfaceContainer: Ink404.i50,
    surfaceContainerHigh: Ink404.i100,
    surfaceContainerHighest: Ink404.i100,
    surfaceDim: Ink404.i100,
    surfaceBright: Ink404.i0,
    outline: Ink404.i200,
    outlineVariant: Ink404.i100,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Ink404.i900,
    onInverseSurface: Ink404.i50,
    inversePrimary: Lime404.l400,
  );

  static ThemeData _build(
    Brightness brightness,
    SessionStatusColors status,
    ArenaColors arena,
  ) {
    final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
    final textTheme = ArenaType.textTheme(scheme.onSurface);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: arena.bg,
      canvasColor: arena.bg,
      fontFamily: ArenaFonts.body,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashColor: arena.primarySoft,
      highlightColor: arena.primarySoft,
      extensions: [status, arena],
      iconTheme: IconThemeData(color: arena.text),
      appBarTheme: AppBarTheme(
        backgroundColor: arena.bg,
        foregroundColor: arena.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ArenaType.h2.copyWith(color: arena.text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: arena.surface,
        indicatorColor: arena.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return ArenaType.micro.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: selected ? arena.primary : arena.textSubtle,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? arena.primary : arena.textSubtle,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: arena.primary,
          foregroundColor: arena.onPrimary,
          disabledBackgroundColor: arena.surfaceRaised,
          disabledForegroundColor: arena.textSubtle,
          minimumSize: const Size.fromHeight(AppSpacing.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: ArenaType.label.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: arena.text,
          backgroundColor: arena.surfaceRaised,
          side: BorderSide(color: arena.borderStrong),
          minimumSize: const Size.fromHeight(AppSpacing.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: ArenaType.label.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: arena.primaryText,
          textStyle: ArenaType.label.copyWith(fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: arena.primary,
        foregroundColor: arena.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: ArenaType.label.copyWith(fontSize: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: arena.surface,
        selectedColor: arena.primarySoft,
        disabledColor: arena.surfaceSunken,
        side: BorderSide(color: arena.border),
        labelStyle: ArenaType.label.copyWith(color: arena.text),
        secondaryLabelStyle: ArenaType.label.copyWith(color: arena.primaryText),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: arena.surface,
        hintStyle: ArenaType.body.copyWith(color: arena.textSubtle),
        labelStyle: ArenaType.caption.copyWith(color: arena.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: border(arena.border),
        enabledBorder: border(arena.border),
        focusedBorder: border(arena.primary, 1.5),
        errorBorder: border(arena.danger),
        focusedErrorBorder: border(arena.danger, 1.5),
      ),
      cardTheme: CardThemeData(
        color: arena.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: arena.border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: arena.surface,
        modalBackgroundColor: arena.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: arena.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: arena.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: ArenaType.h2.copyWith(color: arena.text),
        contentTextStyle: ArenaType.body.copyWith(color: arena.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: arena.surfaceRaised,
        contentTextStyle: ArenaType.body.copyWith(color: arena.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: arena.textMuted,
        textColor: arena.text,
        titleTextStyle: ArenaType.h3.copyWith(color: arena.text, fontSize: 16),
        subtitleTextStyle: ArenaType.caption.copyWith(color: arena.textMuted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? arena.onPrimary : arena.textSubtle),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? arena.primary : arena.surfaceRaised),
        trackOutlineColor: WidgetStateProperty.all(arena.border),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: arena.primary,
        linearTrackColor: arena.tmTrack,
        circularTrackColor: arena.tmTrack,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: arena.primary,
        inactiveTrackColor: arena.tmTrack,
        thumbColor: arena.primary,
      ),
    );
  }
}

extension SessionStatusTheme on BuildContext {
  SessionStatusColors get statusColors =>
      Theme.of(this).extension<SessionStatusColors>() ??
      SessionStatusColors.dark;
}
