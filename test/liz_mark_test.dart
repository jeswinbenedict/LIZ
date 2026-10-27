import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/liz_mark.dart';

/// The Liz mark stands for Liz wherever the app means "Liz does this". As an
/// icon it has to behave like one: sized and coloured by the button, nav bar
/// or pill it sits in.

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(
  MaterialApp(
    theme: LizTheme.app(),
    home: Scaffold(body: Center(child: child)),
  ),
);

Color _ink(WidgetTester t) =>
    (t
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(LizMark),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as LizMarkPainter)
        .color;

void main() {
  testWidgets('as an icon it takes the size and colour of its IconTheme', (
    t,
  ) async {
    await _pump(
      t,
      const IconTheme(
        data: IconThemeData(size: 18, color: Colors.green),
        child: LizMark.icon(),
      ),
    );
    expect(t.getSize(find.byType(LizMark)), const Size(18, 18));
    expect(_ink(t), Colors.green);
  });

  testWidgets('the brand mark is accent red, at the size asked', (t) async {
    await _pump(t, const LizMark(size: 30));
    expect(t.getSize(find.byType(LizMark)), const Size(30, 30));
    final p = LizTheme.app().extension<LizPalette>()!;
    expect(_ink(t), p.accent);
  });

  test('the shapes stay inside the 64-unit square', () {
    for (final o in [...LizMark.stem, ...LizMark.blade]) {
      expect(o.dx, inInclusiveRange(0, 64));
      expect(o.dy, inInclusiveRange(0, 64));
    }
  });
}
