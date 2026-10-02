import 'package:flutter/material.dart';

/// Google's "G" logo, exactly as Google publishes it for Sign in with Google
/// buttons: the four official paths of its 48×48 artwork, in its four
/// colours. Drawn from the path data rather than shipped as an image, so it
/// is crisp at any size and costs no request. Decorative: the button's label
/// says "Continue with Google".
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    ),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  // Google's published artwork (viewBox 0 0 48 48).
  static const _parts = <(Color, String)>[
    (
      Color(0xFFEA4335),
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 '
          '9.5z',
    ),
    (
      Color(0xFF4285F4),
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      Color(0xFFFBBC05),
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      Color(0xFF34A853),
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 '
          '48z',
    ),
  ];

  static final List<(Color, Path)> _paths = [
    for (final (colour, data) in _parts) (colour, svgPath(data)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    for (final (colour, path) in _paths) {
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}

/// A [Path] from SVG path data — the subset Google's logo uses: moveto,
/// lineto, horizontal, vertical, cubic and smooth cubic curves, close, in
/// absolute and relative forms.
@visibleForTesting
Path svgPath(String data) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0; // current point
  var cx = 0.0, cy = 0.0; // last cubic control point, for S
  var startX = 0.0, startY = 0.0;

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final dx = rel ? x : 0.0, dy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = dx + next();
        y = dy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cx = x;
        cy = y;
        // Further pairs after a moveto are linetos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = dx + next();
        y = dy + next();
        path.lineTo(x, y);
        cx = x;
        cy = y;
      case 'H':
        x = (rel ? x : 0) + next();
        path.lineTo(x, y);
        cx = x;
        cy = y;
      case 'V':
        y = (rel ? y : 0) + next();
        path.lineTo(x, y);
        cx = x;
        cy = y;
      case 'C':
        final x1 = dx + next(), y1 = dy + next();
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'S':
        // The first control point mirrors the previous curve's second.
        final x1 = 2 * x - cx, y1 = 2 * y - cy;
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        cx = x;
        cy = y;
      default:
        throw FormatException('Unsupported path command $cmd');
    }
  }
  return path;
}
