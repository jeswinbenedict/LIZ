import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/ask_liz/ask_liz_screen.dart';

/// Drives the screen the way a person does. Without Supabase credentials the
/// app runs on bundled mock data and the on-device ranking, so these exercise
/// the fallback path that a user hits whenever the backend is unreachable.

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: LizTheme.app(), home: const AskLizScreen()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens on the prompt, with examples to choose from', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('What do you want to do?'), findsOneWidget);
    expect(find.text('edit video by transcript'), findsOneWidget);
  });

  testWidgets('answering echoes the question back', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('edit video by transcript'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The asked question stays on screen above the answer.
    expect(find.text('edit video by transcript'), findsWidgets);
    expect(find.text('What do you want to do?'), findsNothing);
  });

  testWidgets('says so plainly when nothing in the catalog fits', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(
      find.byType(TextField),
      'zzzz nonexistent quantum bagel',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // An honest "no match" beats a confident wrong answer.
    expect(find.textContaining("couldn't find a great match"), findsOneWidget);
  });

  testWidgets('a matching question produces results with reasons', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'video');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text("Here's what fits best"), findsOneWidget);
    // Every result explains itself rather than just appearing.
    expect(find.textContaining('Matches "video"'), findsWidgets);
  });

  testWidgets('an empty question is ignored rather than searched', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('What do you want to do?'), findsOneWidget);
  });

  testWidgets('an answer says how many fit, and New question starts over', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'video');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('fit, best first'), findsOneWidget);
    await tester.tap(find.text('New question'));
    await tester.pumpAndSettle();
    expect(find.text('What do you want to do?'), findsOneWidget);
  });
}
