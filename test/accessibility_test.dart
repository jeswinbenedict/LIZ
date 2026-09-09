import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/discover/discover_screen.dart';
import 'package:liz/features/news/news_screen.dart';
import 'package:liz/features/tool_detail/tool_detail_screen.dart';

/// Flutter ships checks for the things that make an interface unusable with a
/// screen reader or on a touch screen: unlabelled controls, tap targets too
/// small to hit, and text that does not meet contrast minimums. Running them in
/// CI keeps a regression from shipping quietly.

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: dark ? LizTheme.dark() : LizTheme.light(),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  testWidgets('Discover meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const DiscoverScreen());

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a tool page meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ToolDetailScreen(toolId: 't-1'));

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('News meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const NewsScreen());

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('dark mode keeps its text readable', (tester) async {
    // The palette is redefined for dark, not merely inverted, so contrast has
    // to be checked on its own rather than inferred from the light theme.
    final handle = tester.ensureSemantics();
    await _pump(tester, const DiscoverScreen(), dark: true);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a dark tool page keeps its text readable', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ToolDetailScreen(toolId: 't-1'), dark: true);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('controls are big enough to hit on a touch screen', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const DiscoverScreen());

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
