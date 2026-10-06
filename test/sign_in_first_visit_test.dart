import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/auth/auth_repository.dart';
import 'package:liz/core/auth/enabled_providers.dart';
import 'package:liz/core/platform/in_app_browser_match.dart';
import 'package:liz/features/auth/sign_in_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 6 October 2026: friends following Liz's link from LinkedIn could not get
/// in. The form greeted them with "Welcome back" on the Sign in tab, and
/// "Continue with Google" failed inside the LinkedIn app, whose built-in
/// browser Google refuses to sign in from.

Future<void> _pump(WidgetTester t, {String? inApp}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        inAppBrowserProvider.overrideWithValue(inApp),
        enabledAuthProvidersProvider.overrideWith(
          (ref) async => const EnabledAuthProviders({'google'}),
        ),
      ],
      child: MaterialApp(
        theme: LizTheme.app(),
        home: const Scaffold(body: SignInView()),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a device nobody has signed in on opens on Create account', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(t);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('someone who has signed in here before sees Sign in', (t) async {
    SharedPreferences.setMockInitialValues({kSignedInBeforeKey: true});
    await _pump(t);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('inside the LinkedIn app it says to open a real browser', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(t, inApp: 'LinkedIn');
    expect(find.textContaining('inside LinkedIn'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('a real browser gets no such note', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(t);
    expect(find.textContaining('Google blocks'), findsNothing);
  });

  test('in-app browsers are told apart from real ones', () {
    const linkedin =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, '
        'like Gecko) Chrome/129.0 Mobile Safari/537.36 [LinkedInApp]/9.30';
    const instagram =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 350';
    const androidWebView =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36';
    const chrome =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/129.0 Safari/537.36';
    const safari =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
        'Safari/604.1';
    expect(inAppBrowserFromUserAgent(linkedin), 'LinkedIn');
    expect(inAppBrowserFromUserAgent(instagram), 'Instagram');
    expect(inAppBrowserFromUserAgent(androidWebView), 'this app');
    expect(inAppBrowserFromUserAgent(chrome), isNull);
    expect(inAppBrowserFromUserAgent(safari), isNull);
  });
}
