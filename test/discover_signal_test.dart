import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/discover/tool_headlines.dart';
import 'package:liz/features/discover/top_movers.dart';

/// Discover's Signal pieces: the movers table can be narrowed to a kind of
/// tool without losing the way back, and headlines that name a tool lead to
/// it.

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/tools/:slug',
        builder: (_, s) => Text('tool ${s.pathParameters['slug']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(theme: LizTheme.app(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  testWidgets('the movers table is a table on a wide screen, leader first', (
    tester,
  ) async {
    await _pump(tester, const TopMovers());
    expect(find.text('WHY IT’S RISING'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
  });

  testWidgets('a kind with nothing rising says so and keeps the filters', (
    tester,
  ) async {
    await _pump(tester, const TopMovers());
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final empty = find.text('Nothing of this kind is rising this week.');
    final rows = find.text('01');
    // Either the demo has image movers, or it says plainly that it has none;
    // the filter row is there in both cases to go back.
    expect(empty.evaluate().isNotEmpty || rows.evaluate().isNotEmpty, isTrue);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('01'), findsOneWidget);
  });

  testWidgets('a headline that names a tool leads to that tool', (
    tester,
  ) async {
    await _pump(tester, const ToolHeadlines());
    expect(find.text('Tools in the headlines'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Scriptly'));
    await tester.pumpAndSettle();
    expect(find.text('tool scriptly'), findsOneWidget);
  });
}
