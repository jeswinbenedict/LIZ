import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The light behind every page (docs/DESIGN.md §2, Ambient): near-black, and
/// a ring of the brand's red — a thin bright core inside a wide soft bloom,
/// brightest at two points where it catches the light, as if a lit halo hung
/// behind the glass. A vignette darkens the edges so the middle reads as
/// depth.
///
/// It is quiet on purpose: the core is under 2 px, the bloom under a fifth
/// opaque, and content sits on surfaces that keep their own contrast. Painted
/// once per size behind a repaint boundary — nothing animates, so it costs a
/// page nothing after its first frame.
class LizAmbient extends StatelessWidget {
  const LizAmbient({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: AmbientPainter(canvas: p.canvas, red: p.accent),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

class AmbientPainter extends CustomPainter {
  const AmbientPainter({required this.canvas, required this.red});
  final Color canvas;
  final Color red;

  @override
  void paint(Canvas c, Size size) {
    final rect = Offset.zero & size;
    c.drawRect(rect, Paint()..color = canvas);
    if (size.isEmpty) return;

    final w = size.width, h = size.height;
    final phone = w < 600;
    // The ring frames the upper middle of the content, a little right of
    // centre (a desktop sidebar takes the left), and runs off the bottom.
    final centre = Offset(w * (phone ? 0.5 : 0.58), h * (phone ? 0.34 : 0.46));
    final radius = phone ? w * 0.72 : math.max(w, h) * 0.4;
    final hot = Color.lerp(red, const Color(0xFFFFB0A8), 0.45)!;

    // A wide red air in the middle: the ring's light filling the room.
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius * 1.25,
          [
            red.withValues(alpha: 0.10),
            red.withValues(alpha: 0.035),
            red.withValues(alpha: 0),
          ],
          const [0, 0.55, 1],
        ),
    );

    // The ring: bloom, glow, core. A sweep gradient varies its strength so it
    // is brightest lower left and upper right, faint between.
    // A full turn from 0 (to the right) clockwise, with the same colour at
    // both ends: a sweep that starts anywhere else wraps with a visible seam.
    // Hot lower left (about 140°) and upper right (about 325°).
    final dim = red.withValues(alpha: 0.18);
    final sweep = ui.Gradient.sweep(
      centre,
      [
        dim,
        red.withValues(alpha: 0.32),
        hot,
        red.withValues(alpha: 0.3),
        dim,
        hot,
        dim,
      ],
      const [0.0, 0.22, 0.39, 0.55, 0.72, 0.9, 1.0],
      TileMode.clamp,
      0,
      math.pi * 2,
    );
    void ring(double width, double sigma, double opacity) {
      c.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      c.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = sweep
          ..maskFilter = sigma > 0
              ? MaskFilter.blur(BlurStyle.normal, sigma)
              : null,
      );
      c.restore();
    }

    ring(radius * 0.32, radius * 0.16, 0.16); // bloom
    ring(radius * 0.07, radius * 0.035, 0.32); // glow
    ring(phone ? 1.4 : 1.8, 0.6, 0.85); // core
    // A faint second rim inside, as light refracting through glass.
    c.drawCircle(
      centre,
      radius * 0.965,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = red.withValues(alpha: 0.12),
    );

    // Where the ring catches the light, a soft flare.
    for (final a in const [math.pi * 0.78, -math.pi * 0.2]) {
      final at = centre + Offset(math.cos(a), math.sin(a)) * radius;
      c.drawCircle(
        at,
        radius * 0.38,
        Paint()
          ..shader = ui.Gradient.radial(
            at,
            radius * 0.38,
            [
              hot.withValues(alpha: 0.16),
              red.withValues(alpha: 0.05),
              red.withValues(alpha: 0),
            ],
            const [0, 0.4, 1],
          ),
      );
    }

    // Vignette: the edges fall back into the dark.
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.45),
          math.max(w, h) * 0.78,
          [
            canvas.withValues(alpha: 0),
            canvas.withValues(alpha: 0),
            canvas.withValues(alpha: 0.7),
          ],
          const [0, 0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(AmbientPainter old) =>
      old.canvas != canvas || old.red != red;
}

/// The page transition the app already used, with [LizAmbient] behind each
/// page inside it: every page is opaque with its own light, so two pages
/// never show through each other while one fades in over the other.
class AmbientPageTransitionsBuilder extends PageTransitionsBuilder {
  const AmbientPageTransitionsBuilder();
  static const _inner = FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    LizAmbient(child: child),
  );
}
