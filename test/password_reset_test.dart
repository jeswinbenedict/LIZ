import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/auth/mock_auth_repository.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/auth/forgot_password_screen.dart';
import 'package:liz/features/auth/password_validation.dart';
import 'package:liz/features/auth/reset_password_screen.dart';
import 'package:liz/features/auth/sign_in_screen.dart';
import 'package:liz/features/auth/sign_in_view.dart';

/// Until this existed, a forgotten password had no route back in: no method on
/// the repository, no screen, and no link anywhere in the app. The only
/// recovery was a magic link, which needs an SMTP provider that is also not
/// configured.

Future<ProviderContainer> _pump(WidgetTester tester, Widget screen) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: LizTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

void main() {
  group('asking for a link', () {
    testWidgets('sends one for a valid address', (tester) async {
      final container = await _pump(tester, const ForgotPasswordScreen());
      final auth = container.read(authRepositoryProvider) as MockAuthRepository;

      await tester.enterText(find.byType(TextField), 'reader@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(auth.lastPasswordResetEmail, 'reader@example.com');
      expect(find.text('Check your inbox'), findsOneWidget);
      await _teardown(tester, container);
    });

    testWidgets('never reveals whether the address has an account', (
      tester,
    ) async {
      // A reset form that says "no account found" is a way to discover who has
      // one, and it is exactly where someone would go looking.
      final container = await _pump(tester, const ForgotPasswordScreen());

      await tester.enterText(find.byType(TextField), 'nobody@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
        find.textContaining('If nobody@example.com has an account'),
        findsOneWidget,
      );
      expect(find.textContaining('not found'), findsNothing);
      expect(find.textContaining("doesn't exist"), findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('catches a malformed address before a round trip', (
      tester,
    ) async {
      final container = await _pump(tester, const ForgotPasswordScreen());
      final auth = container.read(authRepositoryProvider) as MockAuthRepository;

      await tester.enterText(find.byType(TextField), 'not-an-address');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.textContaining("doesn't look right"), findsOneWidget);
      expect(auth.lastPasswordResetEmail, isNull);
      await _teardown(tester, container);
    });

    testWidgets('starts with the address already typed at sign-in', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        const ForgotPasswordScreen(initialEmail: 'reader@example.com'),
      );

      // Retyping it is the small indignity of every reset form.
      expect(find.text('reader@example.com'), findsOneWidget);
      await _teardown(tester, container);
    });
  });

  group('choosing the new password', () {
    testWidgets('a stale link is named as stale, not left to fail on submit', (
      tester,
    ) async {
      // No session means the link was used, expired, or opened elsewhere.
      final container = await _pump(tester, const ResetPasswordScreen());

      expect(find.text('This link has expired'), findsOneWidget);
      expect(find.text('Send a new link'), findsOneWidget);
      expect(find.text('Set password'), findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('with a live session, the form is offered', (tester) async {
      final container = ProviderContainer();
      unawaited(
        container
            .read(authRepositoryProvider)
            .signInWithEmail('reader@example.com', 'whatever'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ResetPasswordScreen()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Set password'), findsOneWidget);
      expect(find.text('This link has expired'), findsNothing);
      await _teardown(tester, container);
    });
  });

  group('what counts as a valid password', () {
    test('length is the bar, and it matches what the server enforces', () {
      expect(validateNewPassword(''), isNotNull);
      expect(validateNewPassword('short'), contains('$minPasswordLength'));
      expect(validateNewPassword('a' * minPasswordLength), isNull);
    });

    test('a long memorable phrase passes, symbols or not', () {
      // Composition rules push people towards Password1! and away from the
      // phrases that are actually harder to guess.
      expect(validateNewPassword('correct horse battery staple'), isNull);
    });

    test('a mistyped confirmation is caught', () {
      expect(
        validateNewPassword('longenough', confirmation: 'longenouhg'),
        contains('do not match'),
      );
      expect(
        validateNewPassword('longenough', confirmation: 'longenough'),
        isNull,
      );
    });

    test('an address is checked permissively', () {
      for (final good in [
        'a@b.co',
        'first.last+tag@example.co.uk',
        'someone@sub.domain.io',
      ]) {
        expect(validateEmail(good), isNull, reason: good);
      }
      for (final bad in [
        '',
        '   ',
        'no-at-sign',
        'missing@tld',
        '@example.com',
      ]) {
        expect(validateEmail(bad), isNotNull, reason: '"$bad"');
      }
    });
  });

  group('reaching it from sign-in', () {
    GoRouter router() => GoRouter(
      initialLocation: '/signin',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Discover home')),
        ),
        GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
        GoRoute(
          path: '/forgot-password',
          builder: (_, s) => ForgotPasswordScreen(
            initialEmail: s.uri.queryParameters['email'],
          ),
        ),
      ],
    );

    testWidgets('Back from the reset screen returns to sign-in', (
      tester,
    ) async {
      // The first version dismissed the sign-in page before pushing, because
      // on a page "onSignedIn" means "signed in, leave". Back then landed on
      // Discover and the half-typed sign-in was gone.
      final r = router();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(theme: LizTheme.light(), routerConfig: r),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);

      r.pop();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Liz'), findsOneWidget);
      expect(find.text('Discover home'), findsNothing);
    });

    testWidgets('carries over an address already typed', (tester) async {
      final r = router();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(theme: LizTheme.light(), routerConfig: r),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField).first, 'me@example.com');
      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();

      expect(find.text('me@example.com'), findsOneWidget);
    });

    testWidgets(
      'from a sheet, the sheet closes so it does not cover the page',
      (tester) async {
        final r = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          const SingleChildScrollView(child: SignInView()),
                    ),
                    child: const Text('open sheet'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/forgot-password',
              builder: (_, _) => const ForgotPasswordScreen(),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(theme: LizTheme.light(), routerConfig: r),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(find.byType(SignInView), findsOneWidget);

        await tester.tap(find.text('Forgot your password?'));
        await tester.pumpAndSettle();

        expect(find.text('Reset your password'), findsOneWidget);
        expect(find.byType(SignInView), findsNothing);
      },
    );
  });
}
