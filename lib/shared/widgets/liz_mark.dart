import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The Liz mark: the circled Z. It stands for Liz everywhere — the brand in
/// the sidebar and top bar (LizWordmark), the head of Ask Liz, and every
/// control or label that means "Liz does this" (Ask Liz, AI summaries), where
/// a generic sparkle used to be.
class LizMark extends StatelessWidget {
  /// The brand: accent red with a soft glow.
  const LizMark({super.key, double this.size = 28, this.color})
    : glow = true,
      _asIcon = false;

  /// In place of an [Icon]: the size and colour of the [IconTheme] around it
  /// unless given (so buttons, nav bars and pills colour it as they would an
  /// icon), and no glow unless asked for.
  const LizMark.icon({super.key, this.size, this.color, this.glow = false})
    : _asIcon = true;

  final double? size;
  final Color? color;
  final bool glow;
  final bool _asIcon;

  /// The artwork leaves a wider margin round the circle than an icon font
  /// leaves round its glyph; drawn this much larger, the two read the same
  /// size side by side.
  static const _iconScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final theme = IconTheme.of(context);
    final box = size ?? (_asIcon ? theme.size ?? 24 : 28);
    final ink = color ?? (_asIcon ? theme.color ?? p.textSecondary : p.accent);
    final drawn = _asIcon ? box * _iconScale : box;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    // The artwork is a single near-black glyph on transparency, tinted.
    // ColorFiltered rather than Image's own `color`: the latter renders
    // nothing under CanvasKit. A blurred copy behind it is its glow.
    Widget glyph(Color tint) => ColorFiltered(
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      child: Image.asset(
        'assets/branding/liz-logo-light.png',
        width: drawn,
        height: drawn,
        cacheWidth: (drawn * dpr).round(),
        cacheHeight: (drawn * dpr).round(),
        filterQuality: FilterQuality.high,
      ),
    );

    final mark = Stack(
      alignment: Alignment.center,
      children: [
        if (glow)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: glyph(p.glow.withValues(alpha: 0.9)),
          ),
        glyph(ink),
      ],
    );
    if (!_asIcon) return mark;
    return SizedBox.square(
      dimension: box,
      // Minimums of zero: a button forcing its 48-pixel tap target on the
      // box must not reach the glyph inside.
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: drawn,
        maxHeight: drawn,
        child: mark,
      ),
    );
  }
}
