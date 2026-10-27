import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/states.dart';

/// A mistyped link lands on a page of the app: it names the address that was
/// asked for and offers ways back in, on a phone and with large text too.

GoRouter _router() => GoRouter(
  initialLocation: '/nope/deeper',
  errorBuilder: (context, state) => NotFoundScreen(path: state.uri.path),
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('Discover home')),
    ),
    GoRoute(
      path: '/news',
      builder: (_, _) => const Scaffold(body: Text('News home')),
    ),
  ],
);

void main() {
  testWidgets('names the address, and its links lead back in', (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(theme: LizTheme.app(), routerConfig: _router()),
    );
    await tester.pumpAndSettle();

    expect(find.text('This page is not here'), findsOneWidget);
    expect(
      find.textContaining('Nothing lives at /nope/deeper'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('News'));
    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();
    expect(find.text('News home'), findsOneWidget);
  });

  testWidgets('fits a small phone with large text, and reads well', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp.router(
        theme: LizTheme.app(),
        routerConfig: _router(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.5,
          maxScaleFactor: 1.5,
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
