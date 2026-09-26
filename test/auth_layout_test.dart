import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/auth/forgot_password_screen.dart';
import 'package:liz/features/auth/reset_password_screen.dart';
import 'package:liz/features/auth/sign_in_screen.dart';

/// The account screens are the ones a person reaches in a hurry — locked out,
/// on a phone, often with the system font turned up — so they get the same
/// layout sweep as the catalog. None of them had any before.
///
/// 560x315 and 800x450 are the viewports a verification run was actually at
/// when an overflow turned up in the console; they stay in the matrix so that
/// question never has to be answered by hand again.

const _sizes = <String, (Size, double)>{
  '320x640 phone': (Size(320, 640), 1.0),
  '320x480 short phone': (Size(320, 480), 1.0),
  '375x812 at 1.5x text': (Size(375, 812), 1.5),
  '800x450 landscape': (Size(800, 450), 1.0),
  '560x315 small window': (Size(560, 315), 1.0),
};

Future<void> _expectFits(
  WidgetTester tester,
  Widget screen,
  Size size,
  double textScale, {
  bool signedIn = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  if (signedIn) {
    unawaited(
      container
          .read(authRepositoryProvider)
          .signInWithEmail('reader@example.com', 'whatever'),
    );
  }

  // Sign-in navigates with go_router, so every screen gets a real router
  // rather than only the ones that happen to need one today.
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: LizTheme.light(),
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
  final error = tester.takeException();

  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();

  expect(error, isNull);
}

void main() {
  for (final size in _sizes.entries) {
    final (dimensions, scale) = size.value;

    testWidgets('sign in fits a ${size.key}', (tester) async {
      await _expectFits(tester, const SignInScreen(), dimensions, scale);
    });

    testWidgets('forgot password fits a ${size.key}', (tester) async {
      await _expectFits(
        tester,
        const ForgotPasswordScreen(),
        dimensions,
        scale,
      );
    });

    testWidgets('an expired reset link fits a ${size.key}', (tester) async {
      await _expectFits(tester, const ResetPasswordScreen(), dimensions, scale);
    });

    testWidgets('the new-password form fits a ${size.key}', (tester) async {
      await _expectFits(
        tester,
        const ResetPasswordScreen(),
        dimensions,
        scale,
        signedIn: true,
      );
    });
  }
}
