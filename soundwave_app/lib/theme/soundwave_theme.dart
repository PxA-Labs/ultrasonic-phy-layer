// Soundwave theme: Material 3 light and dark color schemes (WCAG 2.1 AA).
//
// The schemes are spelled out role by role instead of being derived with
// ColorScheme.fromSeed so the contrast ratios checked in
// test/theme/soundwave_theme_test.dart do not drift with Flutter's tonal
// palette algorithm. Every text role is at least 4.5:1 against every surface
// role it can be drawn on.

import 'package:flutter/material.dart';

/// Status colors for link state, SNR and frame badges. Each one is readable
/// as text (>= 4.5:1) on all surface containers of its brightness.
@immutable
class SignalColors extends ThemeExtension<SignalColors> {
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutral;

  const SignalColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
  });

  static const light = SignalColors(
    success: Color(0xFF1B6E2E),
    warning: Color(0xFF795900),
    danger: Color(0xFFBA1A1A),
    info: Color(0xFF00658F),
    neutral: Color(0xFF5D5F66),
  );

  static const dark = SignalColors(
    success: Color(0xFF6DDB84),
    warning: Color(0xFFF2C14E),
    danger: Color(0xFFFFB4AB),
    info: Color(0xFF7FD0FF),
    neutral: Color(0xFFB0B3BB),
  );

  /// Alpha for tinted badge backgrounds; keeps badge text above 4.5:1.
  static const double badgeAlpha = 0.10;

  /// The theme's signal colors, falling back to the built-in set matching
  /// the theme brightness (e.g. in tests that use a bare MaterialApp).
  static SignalColors of(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = theme.brightness == Brightness.dark ? dark : light;
    return theme.extension<SignalColors>() ?? fallback;
  }

  @override
  SignalColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? neutral,
  }) {
    return SignalColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  SignalColors lerp(ThemeExtension<SignalColors>? other, double t) {
    if (other is! SignalColors) return this;
    return SignalColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

class SoundwaveTheme {
  SoundwaveTheme._();

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0D47A1),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6E3FF),
    onPrimaryContainer: Color(0xFF001B3E),
    secondary: Color(0xFF006874),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF97F0FF),
    onSecondaryContainer: Color(0xFF001F24),
    tertiary: Color(0xFF006874),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF97F0FF),
    onTertiaryContainer: Color(0xFF001F24),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF9F9FF),
    onSurface: Color(0xFF191C20),
    onSurfaceVariant: Color(0xFF43474E),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F3FA),
    surfaceContainer: Color(0xFFEDEDF4),
    surfaceContainerHigh: Color(0xFFE7E8EE),
    surfaceContainerHighest: Color(0xFFE2E2E9),
    outline: Color(0xFF73777F),
    outlineVariant: Color(0xFFC3C6CF),
    inverseSurface: Color(0xFF2E3036),
    onInverseSurface: Color(0xFFF0F0F7),
    inversePrimary: Color(0xFFAAC7FF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF0D47A1),
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFAAC7FF),
    onPrimary: Color(0xFF0A305F),
    primaryContainer: Color(0xFF284777),
    onPrimaryContainer: Color(0xFFD6E3FF),
    secondary: Color(0xFF4FD8EB),
    onSecondary: Color(0xFF00363D),
    secondaryContainer: Color(0xFF004F58),
    onSecondaryContainer: Color(0xFF97F0FF),
    tertiary: Color(0xFF4FD8EB),
    onTertiary: Color(0xFF00363D),
    tertiaryContainer: Color(0xFF004F58),
    onTertiaryContainer: Color(0xFF97F0FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF111318),
    onSurface: Color(0xFFE2E2E9),
    onSurfaceVariant: Color(0xFFC4C6D0),
    surfaceContainerLowest: Color(0xFF0C0E13),
    surfaceContainerLow: Color(0xFF191C20),
    surfaceContainer: Color(0xFF1D2024),
    surfaceContainerHigh: Color(0xFF282A2F),
    surfaceContainerHighest: Color(0xFF33353A),
    outline: Color(0xFF8E9099),
    outlineVariant: Color(0xFF44474E),
    inverseSurface: Color(0xFFE2E2E9),
    onInverseSurface: Color(0xFF2E3036),
    inversePrimary: Color(0xFF415F91),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFFAAC7FF),
  );

  static ThemeData get light => _build(lightScheme, SignalColors.light);

  static ThemeData get dark => _build(darkScheme, SignalColors.dark);

  static ThemeData _build(ColorScheme scheme, SignalColors signal) {
    return ThemeData(
      colorScheme: scheme,
      // 48x48 dp touch targets and standard density on every platform,
      // including desktop where Flutter would otherwise shrink-wrap.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[signal],
    );
  }
}
