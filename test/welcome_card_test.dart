import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/settings_controller.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/discover/welcome_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A first-time visitor used to land on a grid of tools with no word on what
/// Liz is or what an account adds.

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: LizTheme.light(),
        home: const Scaffold(body: WelcomeCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const title = 'Find AI tools while they are still rising';

  testWidgets('a signed-out visitor is told what Liz is', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, [sharedPreferencesProvider.overrideWith((_) => prefs)]);

    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('Save a tool'), findsOneWidget);
  });

  testWidgets('dismissing it is remembered by this browser', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, [sharedPreferencesProvider.overrideWith((_) => prefs)]);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(prefs.getBool('welcome_dismissed'), isTrue);

    // A fresh app on the same browser.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, [sharedPreferencesProvider.overrideWith((_) => prefs)]);
    expect(find.text(title), findsNothing);
  });

  testWidgets('someone signed in already knows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, [
      sharedPreferencesProvider.overrideWith((_) => prefs),
      isSignedInProvider.overrideWithValue(true),
    ]);
    expect(find.text(title), findsNothing);
  });

  testWidgets('it fits a phone at large text and reads to a screen reader', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWith((_) => prefs)],
        child: MaterialApp(
          theme: LizTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(body: SingleChildScrollView(child: WelcomeCard())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
