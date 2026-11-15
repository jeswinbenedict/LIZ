import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/auth_gate.dart';
import 'package:liz/app/router.dart';
import 'package:liz/app/settings_controller.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every page of Liz is behind sign-in. A signed-out visitor goes to sign in,
/// and after signing in lands on the page they asked for; a returning visitor
/// is not bounced to the sign-in form while their session is restored.

String? at(String location, {bool restored = true, bool signedIn = false}) =>
    authRedirect(
      location: Uri.parse(location),
      restored: restored,
      signedIn: signedIn,
    );

void main() {
  group('signed out', () {
    test('every app page goes to sign-in, remembering where it was going', () {
      expect(at('/'), '/signin');
      expect(at('/news'), '/signin?from=%2Fnews');
      expect(at('/tools/elevenlabs'), '/signin?from=%2Ftools%2Felevenlabs');
      expect(at('/search?q=voice'), '/signin?from=%2Fsearch%3Fq%3Dvoice');
    });

    test('sign-in, password help and the legal pages stay open', () {
      for (final open in [
        '/signin',
        '/signin?from=%2Fnews',
        '/forgot-password',
        '/reset-password',
        '/privacy',
        '/terms',
      ]) {
        expect(at(open), isNull, reason: open);
      }
    });
  });

  group('while a session is being restored', () {
    test('app pages wait on the starting screen, not the sign-in form', () {
      expect(at('/news', restored: false), '/starting?from=%2Fnews');
      expect(at('/', restored: false), '/starting');
      expect(at('/starting?from=%2Fnews', restored: false), isNull);
      expect(at('/privacy', restored: false), isNull);
    });

    test('then go on: to the page if signed in, to sign-in if not', () {
      expect(at('/starting?from=%2Fnews', signedIn: true), '/news');
      expect(at('/starting?from=%2Fnews'), '/signin?from=%2Fnews');
      expect(at('/starting'), '/signin');
    });
  });

  group('signed in', () {
    test('pages open, and the sign-in page sends you on', () {
      expect(at('/news', signedIn: true), isNull);
      expect(at('/privacy', signedIn: true), isNull);
      expect(at('/signin', signedIn: true), '/');
      expect(at('/signin?from=%2Fsaved', signedIn: true), '/saved');
    });
  });

  test('the way back cannot leave the site', () {
    expect(safeReturnPath('/tools/x'), Uri.parse('/tools/x'));
    for (final bad in [
      'https://evil.example/',
      '//evil.example',
      r'/\evil.example',
      'javascript:alert(1)',
      '/signin',
      '',
    ]) {
      expect(safeReturnPath(bad), isNull, reason: bad);
    }
    expect(at('/signin?from=https%3A%2F%2Fevil.example', signedIn: true), '/');
  });

  testWidgets('a signed-out visit to a tool page signs in, then shows it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((_) => prefs)],
    );
    addTearDown(container.dispose);
    final auth = container.read(authRepositoryProvider);
    await tester.runAsync(() => auth.restored);
    final gate = AuthGate(auth);
    addTearDown(gate.dispose);
    final router = buildRouter(gate);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: LizTheme.app(), routerConfig: router),
      ),
    );
    router.go('/saved');
    // The sign-in page never settles (its characters breathe and blink).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/signin?from=%2Fsaved',
    );

    await tester.runAsync(auth.signInAsDemo);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/saved');
  });

  group('a new account', () {
    test('goes by way of the welcome, keeping where it was going', () {
      String? fresh(String location) => authRedirect(
        location: Uri.parse(location),
        restored: true,
        signedIn: true,
        welcome: true,
      );
      expect(fresh('/signin'), '/welcome');
      expect(fresh('/signin?from=%2Fsaved'), '/welcome?from=%2Fsaved');
      expect(fresh('/welcome'), isNull);
      expect(safeReturnPath('/welcome'), isNull);
    });

    testWidgets('creating one opens the welcome, and finishing it goes on', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => welcomePending.value = false);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWith((_) => prefs)],
      );
      addTearDown(container.dispose);
      final auth = container.read(authRepositoryProvider);
      await tester.runAsync(() => auth.restored);
      final gate = AuthGate(auth);
      addTearDown(gate.dispose);
      final router = buildRouter(gate);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: LizTheme.app(),
            routerConfig: router,
          ),
        ),
      );
      router.go('/news');
      // The sign-in page's characters breathe and blink for as long as it
      // is open, so it never settles: time is moved on instead.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // A browser nobody has signed in on opens on "Create account".
      expect(find.text('Create your account'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ada');
      await tester.enterText(fields.at(1), 'ada@example.com');
      await tester.enterText(fields.at(2), 'a long enough phrase');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      // Off the sign-in page, so settling works again.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome');
      expect(find.text('Welcome to Liz, Ada'), findsOneWidget);

      await tester.tap(find.text('Skip this step'));
      await tester.pumpAndSettle();
      expect(find.text('Hear when it matters'), findsOneWidget);

      await tester.tap(find.text('Go to Discover'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/news');
      expect(welcomePending.value, isFalse);
    });
  });
}
