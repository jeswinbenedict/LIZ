import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/responsive/adaptive_shell.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/community/community_screen.dart';
import 'package:liz/features/community/post_detail_screen.dart';

/// Community is built and kept out of navigation on purpose, until there are
/// enough people for an empty forum not to be the first thing a visitor sees.
/// Kept means kept working: these screens had no tests of any kind, so a
/// regression would only have surfaced on the day someone switched it on.

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(1000, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/post/:id',
        builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tool/:id',
        builder: (_, _) => const Scaffold(body: Text('tool page')),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, _) => const Scaffold(body: Text('profile page')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: LizTheme.app(),
        routerConfig: router,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  group('the forum', () {
    testWidgets('lists posts', (tester) async {
      await _pump(tester, const CommunityScreen());
      expect(find.textContaining('Lensflow is the first'), findsOneWidget);
    });

    testWidgets('opens a post with its thread', (tester) async {
      await _pump(tester, const PostDetailScreen(postId: 'p-1'));
      expect(find.textContaining('Day 12 of trying'), findsOneWidget);
      // The reply box is the point of a thread page.
      expect(find.widgetWithText(TextField, 'Add a comment…'), findsOneWidget);
    });

    testWidgets('a post that no longer exists says so', (tester) async {
      await _pump(tester, const PostDetailScreen(postId: 'does-not-exist'));
      expect(
        find.textContaining(
          RegExp("not found|no longer|removed|couldn't", caseSensitive: false),
        ),
        findsWidgets,
      );
    });
  });

  group('fits', () {
    const sizes = <String, (Size, double)>{
      '320 wide': (Size(320, 640), 1.0),
      '1.5x text': (Size(375, 812), 1.5),
    };
    for (final size in sizes.entries) {
      final (dimensions, scale) = size.value;
      testWidgets('the forum at ${size.key}', (tester) async {
        await _pump(
          tester,
          const CommunityScreen(),
          size: dimensions,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
      testWidgets('a thread at ${size.key}', (tester) async {
        await _pump(
          tester,
          const PostDetailScreen(postId: 'p-1'),
          size: dimensions,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('stays out of navigation until it is switched on deliberately', () {
    // A decision, not an accident: an empty forum reads worse to a first-time
    // visitor than no tab. Putting it back is one entry in kNavDestinations,
    // and this test is the reminder that doing so is on purpose.
    expect(kNavDestinations.map((d) => d.label), isNot(contains('Community')));
  });
}
