import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/page_header.dart';
import 'package:liz/shared/widgets/pressable.dart';

/// Tab from a filter pill to a mover row. The row's outline was added by
/// changing the tree under it, which rebuilt its InkWell, threw away its
/// focus and sent focus back to the pill — which then kept its ring too.
void main() {
  testWidgets('focus moves on from a pill to an outlined row and stays', (
    tester,
  ) async {
    var rowFocused = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: LizTheme.app(),
        home: Scaffold(
          body: Column(
            children: [
              LizFilterPill(label: 'Image', selected: false, onTap: () {}),
              FocusOutline(
                builder: (context, onFocusChange) => InkWell(
                  onTap: () {},
                  onFocusChange: (v) {
                    rowFocused = v;
                    onFocusChange(v);
                  },
                  child: const SizedBox(height: 40, width: 200),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    List<BoxShadow> pillShadows() =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byType(LizFilterPill),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as ShapeDecoration)
            .shadows ??
        const [];

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(pillShadows(), isNotEmpty, reason: 'the focused pill wears a ring');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(rowFocused, isTrue);
    expect(pillShadows(), isEmpty, reason: 'the pill gives its ring up');
    final outline = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(FocusOutline),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((outline.decoration as BoxDecoration).border, isNotNull);
  });
}
