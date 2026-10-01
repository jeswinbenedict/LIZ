import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/auth/enabled_providers.dart';
import 'package:liz/core/auth/firebase_auth_repository.dart';
import 'package:liz/core/auth/firebase_errors.dart';
import 'package:liz/core/auth/session_expiry.dart';
import 'package:liz/features/auth/reset_password_screen.dart';

/// Sign-in moved to Firebase (migration 0055). What can be checked without
/// Firebase itself: the messages people see, which buttons are offered, how
/// a reset link is recognised, and that an expired Firebase session sends
/// someone to sign in again.

void main() {
  group('messages', () {
    test('a wrong password and an unknown address read the same', () {
      // Which one it was is what someone probing for accounts wants to know.
      final wrong = authErrorMessage('wrong-password');
      expect(authErrorMessage('user-not-found'), wrong);
      expect(authErrorMessage('invalid-credential'), wrong);
      expect(wrong, isNot(contains('no account')));
    });

    test('every code reads as a sentence, never as a code', () {
      for (final code in [
        'email-already-in-use',
        'weak-password',
        'too-many-requests',
        'popup-blocked',
        'operation-not-allowed',
        'configuration-not-found',
        'invalid-totp-code',
        'something-new-firebase-adds',
      ]) {
        final text = authErrorMessage(code);
        expect(text, isNot(contains(code)), reason: code);
        expect(text.endsWith('.'), isTrue, reason: code);
      }
    });
  });

  group('buttons offered', () {
    test('the build lists them; email is always there', () {
      final p = providersFrom('google, Apple');
      expect(p.google, isTrue);
      expect(p.apple, isTrue);
      expect(p.has('email'), isTrue);
    });

    test('an empty list offers email alone', () {
      expect(providersFrom('').hasSocial, isFalse);
    });
  });

  group('reset links', () {
    test('a Firebase reset link is recognised by its mode and code', () {
      expect(
        passwordResetCodeIn(
          Uri.parse(
            'https://liz.example/reset-password?mode=resetPassword'
            '&oobCode=abc123&apiKey=k',
          ),
        ),
        'abc123',
      );
      expect(
        passwordResetCodeIn(
          Uri.parse('https://liz.example/?mode=signIn&oobCode=abc123'),
        ),
        isNull,
        reason: 'a sign-in link is not a reset link',
      );
      expect(
        passwordResetCodeIn(Uri.parse('https://liz.example/reset-password')),
        isNull,
      );
    });

    testWidgets('signed out with a reset code, the form is offered', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LizTheme.app(),
            home: const ResetPasswordScreen(resetCode: 'abc123'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New password'), findsOneWidget);
    });
  });

  test('an expired Firebase session means signing in again', () {
    expect(
      isSessionExpired(FirebaseAuthException(code: 'user-token-expired')),
      isTrue,
    );
    expect(
      isSessionExpired(FirebaseAuthException(code: 'too-many-requests')),
      isFalse,
    );
  });
}
