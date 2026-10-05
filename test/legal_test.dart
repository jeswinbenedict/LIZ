import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/auth/sign_in_view.dart';
import 'package:liz/features/legal/legal_screen.dart';
import 'package:liz/features/profile/settings_screen.dart';

/// Settings listed a privacy policy and terms whose taps did nothing, and
/// sign-up never mentioned either. These pin that both exist, are reachable
/// from where people look for them, and do not cost a half-filled form.

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SingleChildScrollView(child: SignInView()),
            ),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/terms',
      builder: (_, _) => const LegalScreen(document: LegalDocument.terms),
    ),
    GoRoute(
      path: '/privacy',
      builder: (_, _) => const LegalScreen(document: LegalDocument.privacy),
    ),
  ],
);

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final r = _router();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(theme: LizTheme.app(), routerConfig: r),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

void main() {
  testWidgets('Settings opens both documents', (tester) async {
    final r = await _pumpRouter(tester);
    r.push('/settings');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.text('Every visit'), findsOneWidget);

    r.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terms of service'));
    await tester.pumpAndSettle();
    expect(find.text('The catalog'), findsOneWidget);
  });

  testWidgets('sign-up names the terms, and reading them keeps the form', (
    tester,
  ) async {
    final r = await _pumpRouter(tester);
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    // Signing in is not agreeing to anything new, so it stays quiet there.
    expect(find.textContaining('you agree to'), findsNothing);

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('you agree to'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'me@example.com');
    await tester.ensureVisible(find.text('Terms'));
    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of service'), findsOneWidget);

    r.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SignInView), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
  });

  for (final document in [LegalDocument.privacy, LegalDocument.terms]) {
    testWidgets('${document.title} fits a phone and reads to a screen reader', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: LizTheme.app(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: LegalScreen(document: document),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }
}
