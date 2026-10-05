import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/auth/auth_repository.dart';
import 'package:liz/core/auth/mock_auth_repository.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/admin/two_step_gate.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The admin console can publish and remove anything, so once two-step
/// verification is on it opens only for a session that has passed a code
/// check (migration 0042). These pin what a moderator sees at each stage.

class _Auth extends MockAuthRepository {
  _Auth(this.state, {this.staleSignIn = false});
  TwoStep state;
  final bool staleSignIn;
  final List<String> codes = [];
  int signOuts = 0;

  @override
  Future<TotpSetup> startTwoStepSetup() async {
    if (staleSignIn) throw const RecentSignInRequiredException();
    return super.startTwoStepSetup();
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<TwoStep> twoStep() async => state;

  @override
  Future<void> verifyTwoStep(String factorId, String code) async {
    codes.add(code);
    state = const TwoStep(TwoStepStatus.verified);
  }
}

Future<void> _pump(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(
        theme: LizTheme.app(),
        home: const TwoStepGate(child: Text('Console')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a verified session goes straight to the console', (t) async {
    await _pump(t, _Auth(const TwoStep(TwoStepStatus.verified)));
    expect(find.text('Console'), findsOneWidget);
  });

  testWidgets('a code opens the console', (t) async {
    final auth = _Auth(const TwoStep(TwoStepStatus.needsCode, factorId: 'f1'));
    await _pump(t, auth);
    expect(find.text('Console'), findsNothing);
    expect(find.text('Enter your verification code'), findsOneWidget);

    await t.enterText(find.byType(TextField), '12');
    await t.tap(find.text('Verify'));
    await t.pumpAndSettle();
    expect(find.text('Enter the six digits your app shows.'), findsOneWidget);
    expect(auth.codes, isEmpty, reason: 'a short code never leaves the page');

    await t.enterText(find.byType(TextField), '123 456');
    await t.tap(find.text('Verify'));
    await t.pumpAndSettle();
    expect(auth.codes, ['123456']);
    expect(find.text('Console'), findsOneWidget);
  });

  testWidgets('setting up shows a key that can be typed in', (t) async {
    // Tall enough that focusing the code field does not scroll the heading
    // out of the list.
    t.view.physicalSize = const Size(800, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, _Auth(const TwoStep(TwoStepStatus.needsSetup)));
    expect(find.text('Set up two-step verification'), findsOneWidget);
    // MockAuthRepository's setup key, selectable so it can be copied.
    expect(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == 'DEMO'),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('an old sign-in is sent to sign in again, not told to retry', (
    t,
  ) async {
    // 6 Oct 2026: Firebase refused setup for a session from the day before,
    // and the page said only "Something went wrong" with a Try again button
    // that could never work.
    final auth = _Auth(
      const TwoStep(TwoStepStatus.needsSetup),
      staleSignIn: true,
    );
    await _pump(t, auth);
    expect(find.textContaining('sign in again'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await t.tap(find.text('Sign in again'));
    await t.pumpAndSettle();
    expect(auth.signOuts, 1);
  });
}
