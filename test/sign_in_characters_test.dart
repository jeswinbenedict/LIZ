import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/auth/hero/character_stage.dart';
import 'package:liz/features/auth/sign_in_screen.dart';

// The characters beside the sign-in form read it from outside, through focus
// and the password box's visibility (hero/hero_sign_in_layout.dart). These
// check that each state of the real form reaches them.
void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/signin',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: LizTheme.app(), routerConfig: router),
      ),
    );
    // The page never settles (the characters breathe and blink).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  HeroMood mood(WidgetTester tester) =>
      tester.widget<CharacterStage>(find.byType(CharacterStage)).cue.value.mood;

  Future<void> step(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the password box closes their eyes; showing it, they look '
      'away; hiding it, they close them again', (tester) async {
    await open(tester);
    expect(mood(tester), HeroMood.idle);

    await tester.tap(find.widgetWithText(TextField, 'Password'));
    await step(tester);
    expect(mood(tester), HeroMood.privacy);

    await tester.tap(find.byTooltip('Show password'));
    await step(tester);
    expect(mood(tester), HeroMood.peek);

    await tester.tap(find.byTooltip('Hide password'));
    await step(tester);
    expect(mood(tester), HeroMood.privacy);
  });

  testWidgets('a name or email box has them look at it, and leaving the '
      'form lets them go back to following the pointer', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(TextField, 'Email'));
    await step(tester);
    final cue = tester
        .widget<CharacterStage>(find.byType(CharacterStage))
        .cue
        .value;
    expect(cue.mood, HeroMood.attentive);
    expect(cue.target, isNotNull);

    FocusManager.instance.primaryFocus?.unfocus();
    await step(tester);
    expect(mood(tester), HeroMood.idle);
  });
}
