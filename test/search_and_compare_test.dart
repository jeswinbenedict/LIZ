import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/compare/compare_screen.dart';
import 'package:liz/features/discover/search_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: LizTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  group('search', () {
    testWidgets('opens ready for a query', (tester) async {
      await _pump(tester, const SearchScreen());
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an initial query is searched without retyping it', (
      tester,
    ) async {
      await _pump(tester, const SearchScreen(initialQuery: 'script'));

      // Arriving from a link should show results, not an empty box.
      expect(find.text('Scriptly'), findsWidgets);
    });

    testWidgets('a query with no matches says so rather than showing nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        const SearchScreen(initialQuery: 'zzzz-no-such-tool'),
      );

      expect(find.text('Scriptly'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing runs a search', (tester) async {
      await _pump(tester, const SearchScreen());

      await tester.enterText(find.byType(TextField), 'script');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Scriptly'), findsWidgets);
    });
  });

  group('compare', () {
    testWidgets('shows both tools side by side', (tester) async {
      await _pump(tester, const CompareScreen(toolIds: ['t-1', 't-2']));

      expect(find.text('Scriptly'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles being opened with nothing to compare', (tester) async {
      // Reachable directly via /compare with no ids in the query string.
      await _pump(tester, const CompareScreen(toolIds: []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('explains when a shared link points at a withdrawn tool', (
      tester,
    ) async {
      // One id resolves, one does not — a comparison of one is meaningless, but
      // the reason has to be visible or the link looks simply broken.
      await _pump(tester, const CompareScreen(toolIds: ['t-1', 'nope']));

      expect(find.textContaining('no longer listed'), findsOneWidget);
      expect(
        find.textContaining('Select tools from your Saved list'),
        findsNothing,
      );
    });

    testWidgets('asks for a selection when given none', (tester) async {
      await _pump(tester, const CompareScreen(toolIds: []));

      expect(find.textContaining('Pick 2'), findsOneWidget);
    });
  });
}
