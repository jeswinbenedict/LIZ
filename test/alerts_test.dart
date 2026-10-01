import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/alerts/alerts_controller.dart';
import 'package:liz/features/alerts/alerts_screen.dart';

/// Alerts are the payoff for following a tool. Two things have to hold: a
/// guest is told what following would get them rather than shown an empty
/// list, and a signed-in reader sees what happened with the unread ones
/// standing out.

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool signedIn = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  // Deliberately not awaited. The mock sign-in sleeps, and under the test
  // clock only a pump advances time — awaiting it here would wait forever.
  // The pumpAndSettle below carries it to completion.
  if (signedIn) {
    unawaited(
      container
          .read(authRepositoryProvider)
          .signInWithEmail('reader@example.com', 'hunter2'),
    );
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: LizTheme.app(), home: const AlertsScreen()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return container;
}

void main() {
  testWidgets('a guest is told what alerts are for', (tester) async {
    await _pump(tester);

    expect(find.text('Sign in to get alerts'), findsOneWidget);
    // The promise has to name what following actually delivers.
    expect(find.textContaining('pricing changes'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a signed-in reader sees what happened', (tester) async {
    await _pump(tester, signedIn: true);

    expect(find.textContaining('changed its pricing'), findsOneWidget);
    expect(find.textContaining('climbing'), findsOneWidget);
  });

  testWidgets('unread alerts can be cleared in one go', (tester) async {
    final container = await _pump(tester, signedIn: true);
    expect(container.read(alertsControllerProvider).unread, 1);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(container.read(alertsControllerProvider).unread, 0);
    // And the action goes away, because there is nothing left to clear.
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('reading one alert only clears that one', (tester) async {
    final container = await _pump(tester, signedIn: true);
    final controller = container.read(alertsControllerProvider.notifier);
    final first = container.read(alertsControllerProvider).items.first;

    await controller.markRead(first);
    await tester.pumpAndSettle();

    final state = container.read(alertsControllerProvider);
    expect(state.unread, 0);
    expect(state.items.length, 2, reason: 'nothing should disappear');
  });

  testWidgets('the bell stays out of a guest\'s way', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: LizTheme.app(),
          home: const Scaffold(appBar: null, body: Center(child: AlertsBell())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // An empty bell only leads to a sign-in wall, so it is not offered.
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('the bell counts what is waiting', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    unawaited(
      container
          .read(authRepositoryProvider)
          .signInWithEmail('reader@example.com', 'hunter2'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: LizTheme.app(),
          home: const Scaffold(body: Center(child: AlertsBell())),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
