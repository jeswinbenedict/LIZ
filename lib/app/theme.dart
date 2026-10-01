import 'package:flutter/material.dart';

/// Liz's design tokens and theme. docs/DESIGN.md explains every value here;
/// change the two together.
///
/// "Signal", in black and red (1 October 2026): near-black surfaces, one red
/// that marks what can be acted on and what is moving, and thin glowing red
/// light lines — after the TRON: Ares reference the product's owner chose.
/// There is one theme. The previous neutral light/dark pair with an indigo
/// accent is gone, not hidden.
class LizColors {
  const LizColors._();

  /// The red, as a constant for places without a theme to hand (the logo,
  /// generated tiles, the splash). Prefer `context.liz.accent`.
  static const Color brand = Color(0xFFFF2A2A);

  /// The red behind white text: dark enough to carry it (5.2:1).
  static const Color brandFill = Color(0xFFD7141A);

  /// Trending. The same red: in Signal, rising *is* the signal.
  static const Color rising = Color(0xFFFF3B3B);

  /// Free, up, healthy.
  static const Color positive = Color(0xFF34D399);

  /// Paid, warning.
  static const Color warn = Color(0xFFFFB020);

  /// [accent], darkened on a light [background] or lightened on a dark one,
  /// just far enough to reach [minimum] contrast (WCAG: 4.5 for body text).
  ///
  /// The accents above are chosen to be seen, not read. Adjusting lightness
  /// alone keeps the hue, so a badge still reads as the same colour — only
  /// one that can be read.
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

/// The palette (docs/DESIGN.md §2). Read it with `context.liz`.
@immutable
class LizPalette extends ThemeExtension<LizPalette> {
  const LizPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.hairline,
    required this.hairlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentFill,
    required this.accentHover,
    required this.accentSoft,
    required this.positive,
    required this.caution,
    required this.rising,
    required this.danger,
    required this.shadow,
    required this.glow,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color hairline;
  final Color hairlineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Red for text, icons, lines and focus: bright enough to read on black.
  final Color accent;

  /// Red behind white text (primary buttons): dark enough to carry it. The
  /// text red measured 3.5:1 under white.
  final Color accentFill;
  final Color accentHover;
  final Color accentSoft;
  final Color positive;
  final Color caution;
  final Color rising;
  final Color danger;
  final Color shadow;

  /// The light of the light lines: red, used only with blur
  /// ([LizShadows.glow], [GlowLine]).
  final Color glow;

  /// The app's palette.
  static const ares = LizPalette(
    canvas: Color(0xFF050506),
    surface: Color(0xFF0D0E11),
    surfaceMuted: Color(0xFF121318),
    surfaceHover: Color(0xFF191A20),
    hairline: Color(0xFF1F2128),
    hairlineStrong: Color(0xFF2E313A),
    textPrimary: Color(0xFFF4F5F7),
    textSecondary: Color(0xFFA3A7B1),
    textTertiary: Color(0xFF6F7380),
    accent: Color(0xFFFF3B3B),
    accentFill: LizColors.brandFill,
    accentHover: Color(0xFFFF5C5C),
    accentSoft: Color(0x24FF2A2A),
    positive: LizColors.positive,
    caution: LizColors.warn,
    rising: LizColors.rising,
    danger: Color(0xFFFF5A6E),
    shadow: Color(0xFF000000),
    glow: LizColors.brand,
  );

  /// A light page, for one thing only: previewing how the maker badge looks
  /// on someone else's light website (maker_badge.dart). Liz itself has no
  /// light theme.
  static const lightSite = LizPalette(
    canvas: Color(0xFFFBFBFD),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F7),
    surfaceHover: Color(0xFFEFEFF2),
    hairline: Color(0xFFE5E5EA),
    hairlineStrong: Color(0xFFD2D2D7),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFF86868B),
    accent: Color(0xFFD7141A),
    accentFill: Color(0xFFD7141A),
    accentHover: Color(0xFFB80F14),
    accentSoft: Color(0x1AD7141A),
    positive: Color(0xFF248A3D),
    caution: Color(0xFFB25000),
    rising: Color(0xFFD7141A),
    danger: Color(0xFFD70015),
    shadow: Color(0xFF000000),
    glow: Color(0xFFD7141A),
  );

  @override
  LizPalette copyWith() => this;

  @override
  LizPalette lerp(covariant LizPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LizPalette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      hairline: l(hairline, other.hairline),
      hairlineStrong: l(hairlineStrong, other.hairlineStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      accentFill: l(accentFill, other.accentFill),
      accentHover: l(accentHover, other.accentHover),
      accentSoft: l(accentSoft, other.accentSoft),
      positive: l(positive, other.positive),
      caution: l(caution, other.caution),
      rising: l(rising, other.rising),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
      glow: l(glow, other.glow),
    );
  }
}

extension LizPaletteX on BuildContext {
  LizPalette get liz =>
      Theme.of(this).extension<LizPalette>() ?? LizPalette.ares;
}

/// Corner radii (docs/DESIGN.md §4). Tighter than before: Signal is
/// precise rather than soft. Drawn as continuous-corner squircles.
class LizRadius {
  const LizRadius._();
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  /// A continuous-corner shape at [radius].
  static RoundedSuperellipseBorder shape(double radius, {BorderSide? side}) =>
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side ?? BorderSide.none,
      );
}

/// Spacing on a 4-point scale, used in 8-point rhythm (docs/DESIGN.md §4).
class LizSpacing {
  const LizSpacing._();
  static const double xxs = 4;
  static const double xs = 4;
  static const double sm = 8;
  static const double s12 = 12;
  static const double md = 16;
  static const double s20 = 20;
  static const double lg = 24;
  static const double s32 = 32;
  static const double xl = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  /// Horizontal page margin for a width (16 phone, 24 tablet, 32 desktop).
  static double gutter(double width) =>
      width >= 1024 ? 32 : (width >= 600 ? 24 : 16);
}

/// Durations and curves (docs/DESIGN.md §6).
class LizMotion {
  const LizMotion._();
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const emphasized = Duration(milliseconds: 320);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubic;

  /// [duration], or nothing when the reader has asked for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true
      ? Duration.zero
      : duration;
}

/// Depth (docs/DESIGN.md §5). On black a shadow barely shows, so raised
/// things are told apart by a lighter surface and a hairline; the red glow is
/// kept for what is active, selected or primary.
class LizShadows {
  const LizShadows._();
  static List<BoxShadow> raised(LizPalette p) => [
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.5),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> floating(LizPalette p) => [
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.7),
      blurRadius: 40,
      offset: const Offset(0, 12),
    ),
  ];

  /// The red light around something lit: a primary button, the selected tab,
  /// a trend line. [strength] scales it; 1 is a button's.
  static List<BoxShadow> glow(LizPalette p, {double strength = 1}) => [
    BoxShadow(
      color: p.glow.withValues(alpha: (0.45 * strength).clamp(0, 1)),
      blurRadius: 18 * strength,
    ),
  ];
}

/// Button styles beyond the themed defaults (docs/DESIGN.md §7, Buttons).
class LizButtons {
  const LizButtons._();

  /// A secondary action: a red outline that glows faintly, white label.
  static ButtonStyle tonal(LizPalette p) => ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered)
          ? p.glow.withValues(alpha: 0.16)
          : p.accentSoft,
    ),
    foregroundColor: WidgetStatePropertyAll(p.textPrimary),
    side: WidgetStatePropertyAll(
      BorderSide(color: p.accent.withValues(alpha: 0.7)),
    ),
    overlayColor: WidgetStatePropertyAll(p.glow.withValues(alpha: 0.08)),
  );

  /// The shape used for a page's primary call to action.
  static const ButtonStyle capsule = ButtonStyle(
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
    minimumSize: WidgetStatePropertyAll(Size(64, 44)),
  );
}

const String _fontFamily = 'SpaceGrotesk';
const String _monoFamily = 'JetBrainsMono';

/// Text roles (docs/DESIGN.md §3): Space Grotesk for words, JetBrains Mono
/// for the numbers and labels that make Signal read as instruments.
class LizText {
  const LizText._();

  static TextStyle _s(
    double size,
    double height,
    FontWeight weight, [
    double tracking = 0,
    String family = _fontFamily,
  ]) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: tracking,
  );

  static final display = _s(44, 46, FontWeight.w700, -1.4);
  static final largeTitle = _s(32, 36, FontWeight.w700, -0.9);
  static final title1 = _s(26, 31, FontWeight.w700, -0.6);
  static final title2 = _s(21, 26, FontWeight.w600, -0.3);
  static final title3 = _s(18, 23, FontWeight.w600, -0.2);
  static final headline = _s(15, 21, FontWeight.w600, -0.1);
  static final body = _s(15, 22, FontWeight.w400);
  static final callout = _s(14, 20, FontWeight.w400);
  static final subhead = _s(13, 18, FontWeight.w500);
  static final footnote = _s(12, 16, FontWeight.w500, 0.1);
  static final caption = _s(11, 14, FontWeight.w600, 0.3);

  /// Instrument labels: small monospace capitals ("SIGNAL · 30 DAYS").
  /// Write the text in capitals; the style does not transform it.
  static final label = _s(11, 14, FontWeight.w500, 1.0, _monoFamily);

  /// Figures that change in place: ranks, counts, deltas.
  static final mono = _s(13, 18, FontWeight.w500, 0, _monoFamily);

  /// Numbers that change in place keep their width.
  static const tabular = [FontFeature.tabularFigures()];
}

class LizTheme {
  const LizTheme._();

  /// The one theme.
  static ThemeData app() => _build(LizPalette.ares);

  static ThemeData _build(LizPalette p) {
    // Built role by role rather than generated from a seed, so surfaces stay
    // black and the red appears only where it is asked for.
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: p.accent,
      onPrimary: Colors.white,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accentHover,
      secondary: p.textPrimary,
      onSecondary: p.canvas,
      secondaryContainer: p.accentSoft,
      onSecondaryContainer: p.accentHover,
      tertiary: p.rising,
      onTertiary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.danger.withValues(alpha: 0.14),
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceDim: p.canvas,
      surfaceBright: p.surfaceHover,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceHover,
      surfaceContainerHighest: p.surfaceHover,
      outline: p.hairlineStrong,
      outlineVariant: p.hairline,
      shadow: p.shadow,
      scrim: Colors.black,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.canvas,
      inversePrimary: p.accentFill,
      surfaceTint: Colors.transparent,
    );

    final text = TextTheme(
      displayLarge: LizText.display,
      displayMedium: LizText.largeTitle,
      displaySmall: LizText.title1,
      headlineLarge: LizText.largeTitle,
      headlineMedium: LizText.title1,
      headlineSmall: LizText.title2,
      titleLarge: LizText.title3,
      titleMedium: LizText.headline,
      titleSmall: LizText.subhead.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: LizText.body,
      bodyMedium: LizText.callout,
      bodySmall: LizText.footnote,
      labelLarge: LizText.subhead.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: LizText.footnote.copyWith(fontWeight: FontWeight.w600),
      labelSmall: LizText.caption,
    ).apply(bodyColor: p.textPrimary, displayColor: p.textPrimary);

    final buttonText = LizText.subhead.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    final controlShape = LizRadius.shape(LizRadius.sm);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    const buttonMinSize = Size(64, 40);

    WidgetStateProperty<Color?> overlay(Color base) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return base.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered)) {
            return base.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return base.withValues(alpha: 0.12);
          }
          return null;
        });

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      extensions: [p],
      fontFamily: _fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      // No ink ripples: pointer feedback is a quiet hover and press fill.
      splashFactory: NoSplash.splashFactory,
      hoverColor: p.textPrimary.withValues(alpha: 0.04),
      highlightColor: p.textPrimary.withValues(alpha: 0.06),
      focusColor: p.accent.withValues(alpha: 0.16),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: LizText.title3.copyWith(color: p.textPrimary),
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: p.textSecondary, size: 22),
        shape: const Border(bottom: BorderSide(color: Colors.transparent)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      chipTheme: ChipThemeData(
        // The chosen filter is lit: a red edge on a faint red fill. Others
        // are outlines that wait.
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return p.accentSoft;
          if (s.contains(WidgetState.hovered)) return p.surfaceHover;
          return p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.selected)
                ? p.accent
                : p.hairlineStrong,
          ),
        ),
        shape: LizRadius.shape(LizRadius.xs),
        // Plain styles, with the selected one in Material's own slot for it:
        // a state-resolved label style rendered chips with no text at all.
        labelStyle: LizText.subhead.copyWith(color: p.textSecondary),
        secondaryLabelStyle: LizText.subhead.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        showCheckmark: false,
        iconTheme: IconThemeData(color: p.textSecondary, size: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hoverColor: p.surfaceMuted,
        // Placeholders are text, so they get text contrast.
        hintStyle: LizText.body.copyWith(color: p.textSecondary),
        labelStyle: LizText.callout.copyWith(color: p.textSecondary),
        floatingLabelStyle: LizText.footnote.copyWith(color: p.accent),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.hairlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.hairlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          // A primary button is lit: its shadow is red light, stronger when
          // the pointer is on it.
          elevation: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? 0
                : (s.contains(WidgetState.hovered) ? 6 : 3),
          ),
          shadowColor: WidgetStatePropertyAll(p.glow.withValues(alpha: 0.45)),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return p.surfaceHover;
            if (s.contains(WidgetState.hovered)) {
              return const Color(0xFFE41A20);
            }
            return p.accentFill;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? p.textTertiary
                : Colors.white,
          ),
          overlayColor: overlay(Colors.white),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          foregroundColor: WidgetStatePropertyAll(p.textPrimary),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.hovered)
                  ? p.accent
                  : p.hairlineStrong,
            ),
          ),
          overlayColor: overlay(p.glow),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          foregroundColor: WidgetStatePropertyAll(p.accent),
          overlayColor: overlay(p.accent),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(p.textSecondary),
          overlayColor: overlay(p.textPrimary),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(buttonText.copyWith(fontSize: 13)),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.selected)
                  ? p.accent
                  : p.hairlineStrong,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.accentSoft : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? p.textPrimary
                : p.textSecondary,
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accentFill,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 10,
        extendedTextStyle: buttonText,
        shape: LizRadius.shape(LizRadius.md),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => LizText.caption.copyWith(
            letterSpacing: 0.2,
            fontSize: 11,
            color: s.contains(WidgetState.selected)
                ? p.accent
                : p.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? p.accent
                : p.textSecondary,
            shadows: s.contains(WidgetState.selected)
                ? [Shadow(color: p.glow, blurRadius: 10)]
                : null,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: LizText.body.copyWith(color: p.textPrimary),
        subtitleTextStyle: LizText.footnote.copyWith(color: p.textSecondary),
        shape: LizRadius.shape(LizRadius.sm),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 10,
      ),
      dividerTheme: DividerThemeData(color: p.hairline, space: 1, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: LizRadius.shape(
          LizRadius.lg,
          side: BorderSide(color: p.hairlineStrong),
        ),
        titleTextStyle: LizText.title3.copyWith(color: p.textPrimary),
        contentTextStyle: LizText.callout.copyWith(color: p.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: p.hairlineStrong,
        dragHandleSize: const Size(36, 4),
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceMuted,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.shadow,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairlineStrong),
        ),
        textStyle: LizText.callout.copyWith(color: p.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surfaceMuted),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            LizRadius.shape(
              LizRadius.md,
              side: BorderSide(color: p.hairlineStrong),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: p.surfaceHover,
          shape: LizRadius.shape(
            LizRadius.xs,
            side: BorderSide(color: p.hairlineStrong),
          ),
        ),
        textStyle: LizText.footnote.copyWith(color: p.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHover,
        contentTextStyle: LizText.callout.copyWith(color: p.textPrimary),
        actionTextColor: p.accentHover,
        elevation: 0,
        shape: LizRadius.shape(
          LizRadius.sm,
          side: BorderSide(color: p.hairlineStrong),
        ),
        width: null,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentFill : p.surface,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : p.hairlineStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentFill : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: p.hairlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.hairlineStrong,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textSecondary,
        labelStyle: buttonText,
        unselectedLabelStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
        indicatorColor: p.accent,
        dividerColor: p.hairline,
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: overlay(p.textPrimary),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.accentFill,
        textColor: Colors.white,
        textStyle: LizText.caption.copyWith(letterSpacing: 0),
      ),
    );
  }
}

/// A thin red light line, brightest in the middle and fading to nothing at
/// both ends, with a glow — the signature of the Signal look (the seams of
/// light on the TRON: Ares suits it was drawn from). Use it sparingly: under
/// the top bar, over the tab bar, under a section that matters.
class GlowLine extends StatelessWidget {
  const GlowLine({super.key, this.vertical = false, this.strength = 1});

  final bool vertical;

  /// 0–1: how bright. 1 for the bars, less inside content.
  final double strength;

  @override
  Widget build(BuildContext context) {
    final glow = context.liz.glow;
    final fade = glow.withValues(alpha: 0);
    final lit = glow.withValues(alpha: strength.clamp(0, 1));
    return ExcludeSemantics(
      child: Container(
        width: vertical ? 1 : double.infinity,
        height: vertical ? double.infinity : 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
            end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
            colors: [fade, lit, lit, fade],
            stops: const [0, 0.3, 0.7, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: 0.55 * strength),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
