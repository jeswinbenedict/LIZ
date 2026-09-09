import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/discover/discover_screen.dart';
import 'package:liz/features/discover/search_screen.dart';
import 'package:liz/features/news/news_screen.dart';
import 'package:liz/features/tool_detail/tool_detail_screen.dart';
import 'package:liz/features/track/saved_screen.dart';

/// Two settings break layouts more often than anything else: a narrow phone
/// and a reader who has turned the system font up. Both are ordinary, and
/// neither should produce a yellow-and-black overflow stripe.
///
/// 320 logical pixels is the narrowest phone still in circulation; 1.5x is
/// within the range the platform accessibility settings offer.

const _screens = <String, Widget>{
  'Discover': DiscoverScreen(),
  'News': NewsScreen(),
  'Saved': SavedScreen(),
  'Search': SearchScreen(initialQuery: 'video'),
  'Tool detail': ToolDetailScreen(toolId: 't-1'),
};

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LizTheme.light(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  for (final entry in _screens.entries) {
    testWidgets('${entry.key} fits a 320-wide phone', (tester) async {
      await _pump(tester, entry.value, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} survives text scaled to 1.5x', (tester) async {
      await _pump(
        tester,
        entry.value,
        size: const Size(375, 812),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} fits a tablet in portrait', (tester) async {
      await _pump(tester, entry.value, size: const Size(834, 1112));
      expect(tester.takeException(), isNull);
    });
  }
}
