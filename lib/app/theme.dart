import 'package:flutter/material.dart';

/// Liz design tokens + Material 3 light/dark themes.
///
/// Brand feel: modern, discovery-forward, calm surfaces with an electric accent
/// that signals "new / rising". Everything derives from a single seed so the
/// palette stays coherent as the app grows.
class LizColors {
  const LizColors._();

  /// Electric indigo — primary brand seed.
  static const Color brand = Color(0xFF5B5BF5);

  /// Warm "rising / early signal" accent used for trend badges.
  static const Color rising = Color(0xFFFF7A45);

  /// Positive / free pricing.
  static const Color positive = Color(0xFF12B76A);

  /// Warning / paid pricing.
  static const Color warn = Color(0xFFF79009);

  /// [accent], darkened on a light [background] or lightened on a dark one,
  /// just far enough to reach [minimum] contrast (WCAG: 4.5 for body text).
  ///
  /// The accents above are chosen to be seen, not read: orange text on a pale
  /// orange tint measured 2.2:1, and white initials on the green avatar 2.4:1.
  /// Adjusting lightness alone keeps the hue, so a badge still reads as the
  /// same colour — only one that can be read.
  static Color legibleOn(
    Color accent,
    Color background, {
    double minimum = 4.5,
  }) {
    final darken = background.computeLuminance() > 0.4;
    var hsl = HSLColor.fromColor(accent);
    var colour = accent;
    for (var i = 0; i < 40 && contrast(colour, background) < minimum; i++) {
      hsl = hsl.withLightness(
        (hsl.lightness + (darken ? -0.02 : 0.02)).clamp(0.0, 1.0),
      );
      colour = hsl.toColor();
    }
    return colour;
  }

  /// WCAG contrast ratio between two opaque colours, from 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

class LizRadius {
  const LizRadius._();
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

class LizSpacing {
  const LizSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
}

const String _fontFamily = 'Inter';

class LizTheme {
  const LizTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: LizColors.brand,
      brightness: brightness,
    );

    final baseText = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final textTheme = baseText.apply(fontFamily: _fontFamily);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: const TextStyle(fontFamily: _fontFamily).copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LizRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LizRadius.md),
          ),
          textStyle: const TextStyle(fontFamily: _fontFamily).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LizRadius.md),
          ),
          textStyle: const TextStyle(fontFamily: _fontFamily).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
