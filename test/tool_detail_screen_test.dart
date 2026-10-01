import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/tool_detail/tool_detail_screen.dart';

/// The tool page is where a visit ends: it carries the summary, the pricing,
/// and the link out. Without credentials the app serves bundled mock data, so
/// these run against the same code paths a signed-out visitor hits.

Future<void> _pump(WidgetTester tester, String toolId) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LizTheme.light(),
        home: ToolDetailScreen(toolId: toolId),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  testWidgets('shows the tool, its tagline and its summary', (tester) async {
    await _pump(tester, 't-1');

    expect(find.text('Scriptly'), findsWidgets);
    expect(find.textContaining('finished script'), findsWidgets);
    // The AI summary is the reason to read this page rather than the card.
    expect(find.textContaining('Generates full scripts'), findsOneWidget);
  });

  testWidgets('offers the actions a visitor came for', (tester) async {
    await _pump(tester, 't-1');

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Visit website'), findsOneWidget);
  });

  testWidgets('an unknown id fails visibly rather than hanging', (
    tester,
  ) async {
    await _pump(tester, 'does-not-exist');

    // A blank screen would leave someone waiting forever on a dead link.
    final hasMessage = find.textContaining(
      RegExp("not found|couldn't|unavailable", caseSensitive: false),
    );
    expect(hasMessage, findsWidgets);
  });

  testWidgets('renders without overflowing at a phone width', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, 't-1');

    expect(tester.takeException(), isNull);
  });
}
