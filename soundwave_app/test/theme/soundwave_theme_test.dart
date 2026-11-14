// WCAG 2.1 AA contrast checks for the Soundwave light and dark themes.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/theme/soundwave_theme.dart';

/// WCAG 2.1 contrast ratio (1.0 to 21.0) between two opaque colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const double aaText = 4.5;

class Pair {
  final Color fg;
  final Color bg;
  const Pair(this.fg, this.bg);
}

class Variant {
  final ColorScheme scheme;
  final SignalColors signal;
  final ThemeData theme;
  const Variant(this.scheme, this.signal, this.theme);
}

/// A status color's tinted badge background drawn over a card.
Color badgeBackground(Color status, ColorScheme scheme) {
  final tint = status.withValues(alpha: SignalColors.badgeAlpha);
  return Color.alphaBlend(tint, scheme.surfaceContainerLow);
}

void expectReadable(Map<String, Pair> pairs) {
  for (final entry in pairs.entries) {
    expect(
      contrastRatio(entry.value.fg, entry.value.bg),
      greaterThanOrEqualTo(aaText),
      reason: '${entry.key} is below WCAG AA 4.5:1',
    );
  }
}

void main() {
  test('contrast helper matches known WCAG values', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21.0, 0.01));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1.0, 0.01));
    // #767676 on white is the classic "just passes AA" grey (4.54:1).
    expect(
      contrastRatio(const Color(0xFF767676), Colors.white),
      closeTo(4.54, 0.01),
    );
  });

  final variants = <String, Variant>{
    'light': Variant(
      SoundwaveTheme.lightScheme,
      SignalColors.light,
      SoundwaveTheme.light,
    ),
    'dark': Variant(
      SoundwaveTheme.darkScheme,
      SignalColors.dark,
      SoundwaveTheme.dark,
    ),
  };

  for (final variant in variants.entries) {
    final scheme = variant.value.scheme;
    final signal = variant.value.signal;
    final theme = variant.value.theme;

    group('${variant.key} theme', () {
      final surfaces = <String, Color>{
        'surface': scheme.surface,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
      };

      test('on-colors are readable on their filled roles', () {
        expectReadable({
          'onPrimary/primary': Pair(scheme.onPrimary, scheme.primary),
          'onPrimaryContainer/primaryContainer': Pair(
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ),
          'onSecondary/secondary': Pair(scheme.onSecondary, scheme.secondary),
          'onSecondaryContainer/secondaryContainer': Pair(
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          'onTertiary/tertiary': Pair(scheme.onTertiary, scheme.tertiary),
          'onError/error': Pair(scheme.onError, scheme.error),
          'onErrorContainer/errorContainer': Pair(
            scheme.onErrorContainer,
            scheme.errorContainer,
          ),
          'onInverseSurface/inverseSurface': Pair(
            scheme.onInverseSurface,
            scheme.inverseSurface,
          ),
        });
      });

      test('text roles are readable on every surface container', () {
        final textRoles = <String, Color>{
          'onSurface': scheme.onSurface,
          'onSurfaceVariant': scheme.onSurfaceVariant,
          'primary': scheme.primary,
          'secondary': scheme.secondary,
          'error': scheme.error,
        };
        expectReadable({
          for (final fg in textRoles.entries)
            for (final bg in surfaces.entries)
              '${fg.key}/${bg.key}': Pair(fg.value, bg.value),
        });
      });

      test('signal colors are readable as text and in tinted badges', () {
        final statuses = <String, Color>{
          'success': signal.success,
          'warning': signal.warning,
          'danger': signal.danger,
          'info': signal.info,
          'neutral': signal.neutral,
        };
        expectReadable({
          for (final fg in statuses.entries)
            for (final bg in surfaces.entries)
              '${fg.key}/${bg.key}': Pair(fg.value, bg.value),
          // Badges: text on a badgeAlpha tint of itself over a card.
          for (final fg in statuses.entries)
            '${fg.key} badge': Pair(
              fg.value,
              badgeBackground(fg.value, scheme),
            ),
        });
      });

      test('ThemeData carries the scheme, signal colors and 48dp targets', () {
        expect(theme.colorScheme.brightness, scheme.brightness);
        expect(theme.colorScheme.primary, scheme.primary);
        expect(theme.colorScheme.surface, scheme.surface);
        expect(theme.extension<SignalColors>(), same(signal));
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      });
    });
  }

  test('SignalColors lerp and copyWith', () {
    final mid = SignalColors.light.lerp(SignalColors.dark, 1.0);
    expect(mid.success, SignalColors.dark.success);
    expect(SignalColors.light.lerp(null, 0.5), same(SignalColors.light));
    final copy = SignalColors.light.copyWith(info: Colors.black);
    expect(copy.info, Colors.black);
    expect(copy.success, SignalColors.light.success);
  });
}
