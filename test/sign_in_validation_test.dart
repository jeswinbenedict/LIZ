import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/auth/sign_in_view.dart';

/// Submitting an empty form used to reach Supabase and come back with a generic
/// "invalid credentials", which is a slow way to learn you left a box blank.

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LizTheme.app(),
        home: const Scaffold(body: SignInView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Sign in').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty form asks for the email first', (tester) async {
    await _pump(tester);
    await _submit(tester);

    expect(find.text('Enter your email address.'), findsOneWidget);
  });

  testWidgets('a malformed address is caught before the network', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await _submit(tester);

    expect(find.textContaining("doesn't look right"), findsOneWidget);
  });

  testWidgets('a valid address with no password says which box is empty', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'someone@example.com');
    await _submit(tester);

    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('addresses with plus tags and subdomains are accepted', (
    tester,
  ) async {
    // Over-strict patterns reject perfectly valid addresses; these are real.
    for (final email in [
      'a+tag@example.co.uk',
      'first.last@mail.example.com',
    ]) {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, email);
      await _submit(tester);

      expect(
        find.textContaining("doesn't look right"),
        findsNothing,
        reason: '$email should be accepted',
      );
    }
  });
}
