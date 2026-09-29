import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Liz's signal line: how one measure moved, day by day.
///
/// One accent-coloured line with a faint fill beneath and a dot on today's
/// value — drawn the same way wherever it appears, so it reads as the same
/// thing on a chart row and on a tool page. It never shows a scale: the words
/// beside it carry the numbers ("76.2k → 76.9k stars").
class SignalSparkline extends StatelessWidget {
  const SignalSparkline({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.width = 64,
    this.height = 22,
    this.strokeWidth = 1.5,
  });

  final List<double> values;
  final String semanticLabel;
  final double width;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: values,
            line: p.accent,
            fill: p.accentSoft,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color line;
  final Color fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi - lo;
    // Room for the end dot, so it is never clipped.
    final pad = strokeWidth * 2;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    Offset at(int i) {
      final x = pad + w * i / (values.length - 1);
      // A flat series sits in the middle rather than on the floor.
      final t = span == 0 ? 0.5 : (values[i] - lo) / span;
      return Offset(x, pad + h * (1 - t));
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final o = at(i);
      path.lineTo(o.dx, o.dy);
    }
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      at(values.length - 1),
      strokeWidth * 1.6,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.line != line || old.fill != fill;
}
