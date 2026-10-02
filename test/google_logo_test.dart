import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/shared/widgets/google_logo.dart';

/// The "Continue with Google" button carries Google's own logo, drawn from
/// its published path data. These pin that the data is read whole: each
/// coloured part lands where Google's artwork puts it.

void main() {
  test('the four parts fill the 48×48 artwork', () {
    // Red runs across the top, blue down the right, yellow on the left,
    // green along the bottom.
    final red = svgPath(
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
      '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
    ).getBounds();
    expect(red.top, closeTo(0, 0.01));
    expect(red.left, closeTo(2.56, 0.01));
    expect(red.right, closeTo(40.06, 0.01));

    final green = svgPath(
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
      '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
    ).getBounds();
    expect(green.bottom, closeTo(48, 0.01));
  });

  test('a smooth curve mirrors the previous control point', () {
    final p = svgPath('M0 0C0 10 10 10 10 0s10-10 10 0z');
    expect(p.getBounds().right, closeTo(20, 0.01));
  });

  testWidgets('renders without errors at button and large sizes', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFF0D0E11),
              padding: const EdgeInsets.all(16),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoogleLogo(),
                  SizedBox(width: 16),
                  GoogleLogo(size: 160),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Kept for a look by eye when the artwork changes: build/google_logo.png.
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/google_logo.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    });
  });
}
