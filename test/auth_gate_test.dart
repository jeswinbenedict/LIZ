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
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/signin?from=%2Fsaved',
    );

    await tester.runAsync(auth.signInAsDemo);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/saved');
  });
}
