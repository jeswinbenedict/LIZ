import 'package:flutter/material.dart';

/// Liz's design tokens and themes. docs/DESIGN.md explains every value here;
/// change the two together.
///
/// Neutral greys carry the interface and one indigo accent marks what can be
/// acted on. The previous theme generated everything from a single seed colour,
/// which tinted every surface lavender and read as a template.
class LizColors {
  const LizColors._();

  /// The accent, as a constant for places without a theme to hand (the logo,
  /// generated tiles). Prefer `context.liz.accent`, which adapts to the theme.
  static const Color brand = Color(0xFF5856D6);

  /// Trending. Used as a cue next to a number, never as body text.
  static const Color rising = Color(0xFFFF7A45);

  /// Free, up, healthy.
  static const Color positive = Color(0xFF34C759);

  /// Paid, warning.
  static const Color warn = Color(0xFFFF9F0A);

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

/// The theme-dependent palette (docs/DESIGN.md §2). Read it with `context.liz`.
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
  final Color accent;

  /// The accent behind white text (primary buttons). In dark mode the text
  /// accent is too light to carry white: #7B79FF measured 3.7:1.
  final Color accentFill;
  final Color accentHover;
  final Color accentSoft;
  final Color positive;
  final Color caution;
  final Color rising;
  final Color danger;
  final Color shadow;

  static const light = LizPalette(
    canvas: Color(0xFFFBFBFD),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F7),
    surfaceHover: Color(0xFFEFEFF2),
    hairline: Color(0xFFE5E5EA),
    hairlineStrong: Color(0xFFD2D2D7),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFF86868B),
    accent: Color(0xFF5856D6),
    accentFill: Color(0xFF5856D6),
    accentHover: Color(0xFF4B49C8),
    accentSoft: Color(0x1A5856D6),
    positive: Color(0xFF248A3D),
    caution: Color(0xFFB25000),
    rising: Color(0xFFC93400),
    danger: Color(0xFFD70015),
    shadow: Color(0xFF000000),
  );

  static const dark = LizPalette(
    canvas: Color(0xFF0A0A0B),
    surface: Color(0xFF161618),
    surfaceMuted: Color(0xFF1C1C1E),
    surfaceHover: Color(0xFF232326),
    hairline: Color(0xFF2C2C2E),
    hairlineStrong: Color(0xFF3A3A3C),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA1A1A6),
    textTertiary: Color(0xFF8A8A8F),
    accent: Color(0xFF7B79FF),
    accentFill: Color(0xFF5E5CE6),
    accentHover: Color(0xFF8E8CFF),
    accentSoft: Color(0x2E7B79FF),
    positive: Color(0xFF30D158),
    caution: Color(0xFFFF9F0A),
    rising: Color(0xFFFF7A45),
    danger: Color(0xFFFF453A),
    shadow: Color(0xFF000000),
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
    );
  }
}

extension LizPaletteX on BuildContext {
  LizPalette get liz =>
      Theme.of(this).extension<LizPalette>() ?? LizPalette.light;
}

/// Corner radii (docs/DESIGN.md §4). Drawn as continuous-corner squircles.
class LizRadius {
  const LizRadius._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  /// Apple's continuous-corner shape at [radius].
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

/// Shadows for the raised and floating materials (docs/DESIGN.md §5).
class LizShadows {
  const LizShadows._();
  static List<BoxShadow> raised(LizPalette p) => [
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> floating(LizPalette p) => [
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.12),
      blurRadius: 40,
      offset: const Offset(0, 12),
    ),
  ];
}

/// Button styles beyond the themed defaults (docs/DESIGN.md §7, Buttons).
class LizButtons {
  const LizButtons._();

  /// Accent label on a soft accent fill: a secondary action that still reads
  /// as clickable. `FilledButton.tonal` would inherit the solid accent from
  /// the theme, so this is set explicitly.
  static ButtonStyle tonal(LizPalette p) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered)
          ? p.accent.withValues(alpha: 0.16)
          : p.accentSoft,
    ),
    foregroundColor: WidgetStatePropertyAll(
      LizColors.legibleOn(p.accent, Color.alphaBlend(p.accentSoft, p.surface)),
    ),
    overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.06)),
  );

  /// The capsule used for a page's primary call to action.
  static const ButtonStyle capsule = ButtonStyle(
    shape: WidgetStatePropertyAll(StadiumBorder()),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
    minimumSize: WidgetStatePropertyAll(Size(64, 44)),
  );
}

const String _fontFamily = 'Inter';

/// Text roles after Apple's text styles, sized for the web (docs/DESIGN.md §3).
class LizText {
  const LizText._();

  static TextStyle _s(
    double size,
    double height,
    FontWeight weight, [
    double tracking = 0,
  ]) => TextStyle(
    fontFamily: _fontFamily,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: tracking,
  );

  static final display = _s(40, 44, FontWeight.w700, -1.2);
  static final largeTitle = _s(32, 38, FontWeight.w700, -0.8);
  static final title1 = _s(26, 32, FontWeight.w700, -0.5);
  static final title2 = _s(21, 27, FontWeight.w600, -0.3);
  static final title3 = _s(18, 24, FontWeight.w600, -0.2);
  static final headline = _s(15, 21, FontWeight.w600, -0.1);
  static final body = _s(15, 22, FontWeight.w400);
  static final callout = _s(14, 20, FontWeight.w400);
  static final subhead = _s(13, 18, FontWeight.w500);
  static final footnote = _s(12, 16, FontWeight.w500, 0.1);
  static final caption = _s(11, 14, FontWeight.w600, 0.3);

  /// Numbers that change in place (ranks, counts) keep their width.
  static const tabular = [FontFeature.tabularFigures()];
}

class LizTheme {
  const LizTheme._();

  static ThemeData light() => _build(Brightness.light, LizPalette.light);
  static ThemeData dark() => _build(Brightness.dark, LizPalette.dark);

  static ThemeData _build(Brightness brightness, LizPalette p) {
    final isDark = brightness == Brightness.dark;

    // Built role by role rather than generated from a seed, so surfaces stay
    // neutral and the accent appears only where it is asked for.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: Colors.white,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accent,
      secondary: p.textPrimary,
      onSecondary: p.surface,
      secondaryContainer: p.accentSoft,
      onSecondaryContainer: isDark ? p.accentHover : p.accent,
      tertiary: p.rising,
      onTertiary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.danger.withValues(alpha: 0.12),
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceDim: p.canvas,
      surfaceBright: p.surface,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceHover,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.hairlineStrong,
      outlineVariant: p.hairline,
      shadow: p.shadow,
      scrim: Colors.black,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.canvas,
      inversePrimary: p.accentHover,
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
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      fontFamily: _fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      // No ink ripples: pointer feedback is a quiet hover and press fill, as
      // on Apple's platforms and the web generally.
      splashFactory: NoSplash.splashFactory,
      hoverColor: p.textPrimary.withValues(alpha: 0.04),
      highlightColor: p.textPrimary.withValues(alpha: 0.06),
      focusColor: p.accent.withValues(alpha: 0.12),
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
        shape: Border(bottom: BorderSide(color: Colors.transparent)),
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
        // Monochrome selection: the chosen pill inverts to the text colour, so
        // filters never compete with the accent that marks actions.
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return p.textPrimary;
          if (s.contains(WidgetState.hovered)) return p.surfaceHover;
          return p.surfaceMuted;
        }),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        // Plain styles, with the selected one in Material's own slot for it:
        // a state-resolved label style rendered chips with no text at all.
        labelStyle: LizText.subhead.copyWith(color: p.textPrimary),
        secondaryLabelStyle: LizText.subhead.copyWith(
          color: p.canvas,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        showCheckmark: false,
        iconTheme: IconThemeData(color: p.textSecondary, size: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hoverColor: p.surfaceHover,
        // Placeholders are text, so they get text contrast; tertiary is
        // 3.6:1 on white, fine for icons and too faint to read.
        hintStyle: LizText.body.copyWith(color: p.textSecondary),
        labelStyle: LizText.callout.copyWith(color: p.textSecondary),
        floatingLabelStyle: LizText.footnote.copyWith(color: p.accent),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LizRadius.sm),
          borderSide: BorderSide(color: p.hairline),
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
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return p.surfaceHover;
            final base = p.accentFill;
            // Hover darkens by a step in either theme, so white stays legible.
            if (s.contains(WidgetState.hovered)) {
              return Color.alphaBlend(
                Colors.black.withValues(alpha: 0.1),
                base,
              );
            }
            return base;
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
          backgroundColor: WidgetStatePropertyAll(p.surface),
          side: WidgetStatePropertyAll(BorderSide(color: p.hairlineStrong)),
          overlayColor: overlay(p.textPrimary),
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
          side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? p.surface : p.surfaceMuted,
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
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: buttonText,
        shape: const StadiumBorder(),
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
            letterSpacing: 0,
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
        shape: LizRadius.shape(LizRadius.lg),
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
        dragHandleSize: const Size(36, 5),
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.shadow.withValues(alpha: 0.4),
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
        textStyle: LizText.callout.copyWith(color: p.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            LizRadius.shape(LizRadius.md, side: BorderSide(color: p.hairline)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFF1D1D1F),
          shape: LizRadius.shape(LizRadius.xs),
        ),
        textStyle: LizText.footnote.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF1D1D1F),
        contentTextStyle: LizText.callout.copyWith(color: Colors.white),
        actionTextColor: isDark ? p.accentHover : const Color(0xFFA5A4FF),
        elevation: 0,
        shape: LizRadius.shape(LizRadius.sm),
        width: null,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.positive : p.surfaceHover,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        side: BorderSide(color: p.hairlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
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
        backgroundColor: p.danger,
        textColor: Colors.white,
        textStyle: LizText.caption.copyWith(letterSpacing: 0),
      ),
    );
  }
}
