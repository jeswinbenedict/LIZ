import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The Liz mark, "the Rise": the stem of the l, and beside it a blade rising
/// from the baseline — a tool climbing past the rest. Two flat shapes on a
/// 64-unit grid, no outline, no glow, so it holds from a 16-pixel favicon to
/// a billboard (docs/DESIGN.md §2, Brand).
///
/// It stands for Liz everywhere: beside the wordmark ([LizWordmark]), at the
/// head of Ask Liz, and on every control that means "Liz does this".
class LizMark extends StatelessWidget {
  /// The brand: in accent red.
  const LizMark({super.key, double this.size = 28, this.color})
    : _asIcon = false;

  /// In place of an [Icon]: the size and colour of the [IconTheme] around it
  /// unless given, so buttons, nav bars and pills colour it as they would an
  /// icon.
  const LizMark.icon({super.key, this.size, this.color}) : _asIcon = true;

  final double? size;
  final Color? color;
  final bool _asIcon;

  /// The two shapes, in units of a 64-square: the stem, then the blade.
  /// The same points draw the app icons (tool/brand/make_icons.py).
  static const stem = [
    Offset(10, 6),
    Offset(24, 6),
    Offset(24, 58),
    Offset(10, 58),
  ];
  static const blade = [
    Offset(30, 44),
    Offset(56, 24),
    Offset(56, 38),
    Offset(30, 58),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final theme = IconTheme.of(context);
    final box = size ?? (_asIcon ? theme.size ?? 24 : 28);
    final ink = color ?? (_asIcon ? theme.color ?? p.textSecondary : p.accent);
    return SizedBox.square(
      dimension: box,
      child: CustomPaint(painter: LizMarkPainter(ink)),
    );
  }
}

/// Paints [LizMark.stem] and [LizMark.blade] scaled to the canvas.
class LizMarkPainter extends CustomPainter {
  const LizMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 64;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (final shape in const [LizMark.stem, LizMark.blade]) {
      canvas.drawPath(
        Path()..addPolygon([for (final o in shape) o * unit], true),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(LizMarkPainter old) => old.color != color;
}
