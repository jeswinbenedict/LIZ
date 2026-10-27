import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/admin/admin_screen.dart';
import 'package:liz/features/news/news_screen.dart';
import 'package:liz/features/track/saved_screen.dart';
import 'package:liz/shared/widgets/news_card.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: LizTheme.app(), home: screen),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  group('news', () {
    testWidgets('lists articles', (tester) async {
      await _pump(tester, const NewsScreen());

      expect(find.text('News'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stories sit under their day, and an outlet can be picked', (
      tester,
    ) async {
      await _pump(tester, const NewsScreen());

      // The newest mock stories are hours old: today, or yesterday when the
      // test runs in the small hours.
      expect(find.textContaining(RegExp(r'^(Today|Yesterday)$')), findsWidgets);
      // The lead story is from Hacker News: its byline beside the pill.
      expect(find.text('Hacker News'), findsNWidgets(2));
      // The pills come before the stories, so the first is the pill.
      await tester.tap(find.text('TechCrunch').first);
      await tester.pumpAndSettle();
      expect(find.text('Hacker News'), findsOneWidget);
      expect(find.byType(NewsCard), findsWidgets);

      await tester.tap(find.text('All').first);
      await tester.pumpAndSettle();
      expect(find.text('Hacker News'), findsNWidgets(2));
    });

    test('a story is filed under today, yesterday, this week or earlier', () {
      final now = DateTime(2026, 10, 28, 15);
      expect(newsDay(DateTime(2026, 10, 28, 1), now: now), 'Today');
      expect(newsDay(DateTime(2026, 10, 27, 23), now: now), 'Yesterday');
      expect(newsDay(DateTime(2026, 10, 23), now: now), 'This week');
      expect(newsDay(DateTime(2026, 10, 1), now: now), 'Earlier');
    });

    testWidgets('survives a phone-width layout', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, const NewsScreen());
      expect(tester.takeException(), isNull);
    });
  });

  group('saved', () {
    testWidgets('asks a guest to sign in rather than showing an empty list', (
      tester,
    ) async {
      // A signed-out visitor has no list; "nothing saved" would be misleading.
      await _pump(tester, const SavedScreen());

      expect(
        find.textContaining(RegExp('sign in', caseSensitive: false)),
        findsWidgets,
      );
    });
  });

  group('admin', () {
    testWidgets('does not expose moderation tools to a guest', (tester) async {
      // The screen is reachable at /admin by anyone who types the URL. Server
      // policies are the real defence, but it must not present the controls.
      await _pump(tester, const AdminScreen());

      expect(tester.takeException(), isNull);
      // Assert the gate itself, not merely the absence of controls — an empty
      // screen would satisfy a weaker check while telling the visitor nothing.
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(
        find.textContaining(RegExp('approve', caseSensitive: false)),
        findsNothing,
      );
    });
  });
}
