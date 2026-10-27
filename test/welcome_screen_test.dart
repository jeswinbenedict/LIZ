import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/onboarding/welcome_screen.dart';
import 'package:liz/features/profile/preferences.dart';
import 'package:liz/shared/widgets/page_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The welcome a new account opens on: interests, then alerts, both saved,
/// and both skippable. It is the first page a new person sees, so it gets the
/// small-phone and large-text checks too.

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(returnTo: '/news'),
      ),
      GoRoute(path: '/news', builder: (_, _) => const Text('News home')),
      GoRoute(path: '/', builder: (_, _) => const Text('Discover home')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('saves the interests and alerts chosen, then goes on', (
    tester,
  ) async {
    final container = await _pump(tester);

    expect(find.text('Skip this step'), findsOneWidget);
    await tester.tap(find.byType(LizFilterPill).first);
    await tester.pumpAndSettle();
    expect(find.text('1 chosen'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Price changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Discover'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('News home'), findsOneWidget);
    final prefs = container.read(preferencesProvider);
    expect(prefs.interests, hasLength(1));
    expect(prefs.pricingAlerts, isFalse);
    expect(prefs.risingAlerts, isTrue);
  });

  testWidgets('Skip leaves at once, choosing nothing', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Skip'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('News home'), findsOneWidget);
    expect(container.read(preferencesProvider).interests, isEmpty);
  });

  for (final step in [0, 1]) {
    testWidgets('step ${step + 1} fits a small phone with large text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, size: const Size(320, 640), textScale: 1.5);
      if (step == 1) {
        await tester.tap(find.text('Skip this step'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }
}
