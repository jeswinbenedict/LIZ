import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/liz_mark.dart';

/// The Liz mark replaced the generic sparkle wherever the app means "Liz does
/// this". As an icon it has to behave like one: sized and coloured by the
/// button, nav bar or pill it sits in.

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(
  MaterialApp(
    theme: LizTheme.app(),
    home: Scaffold(body: Center(child: child)),
  ),
);

ColorFilter _glyphFilter(WidgetTester t) =>
    // The last is the glyph; a glow, when drawn, comes first.
    t.widgetList<ColorFiltered>(find.byType(ColorFiltered)).last.colorFilter;

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
    expect(
      _glyphFilter(t),
      const ColorFilter.mode(Colors.green, BlendMode.srcIn),
    );
    expect(find.byType(ImageFiltered), findsNothing, reason: 'no glow');
  });

  testWidgets('the brand mark glows in the accent', (t) async {
    await _pump(t, const LizMark(size: 30));
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(t.getSize(find.byType(LizMark)), const Size(30, 30));
  });
}
