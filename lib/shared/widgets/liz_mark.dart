import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The Liz mark: the circled Z, in the accent red with a soft glow. Used by
/// the sidebar and top bar (LizWordmark) and wherever Liz itself speaks, such
/// as the head of Ask Liz.
class LizMark extends StatelessWidget {
  const LizMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final p = context.liz;
    // The artwork is a single near-black glyph on transparency, tinted red.
    // ColorFiltered rather than Image's own `color`: the latter renders
    // nothing under CanvasKit. A blurred copy behind it is its glow.
    Widget glyph(Color color) => ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        'assets/branding/liz-logo-light.png',
        width: size,
        height: size,
        cacheWidth: (size * dpr).round(),
        cacheHeight: (size * dpr).round(),
        filterQuality: FilterQuality.high,
      ),
    );
    return Stack(
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: glyph(p.glow.withValues(alpha: 0.9)),
        ),
        glyph(p.accent),
      ],
    );
  }
}
