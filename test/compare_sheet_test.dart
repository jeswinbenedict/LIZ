import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/compare/compare_sheet.dart';

/// Comparing used to start only from Saved, in selection mode. From a tool's
/// own page you now pick one or two of its alternatives and the comparison
/// opens at a shareable address.

void main() {
  testWidgets('pick alternatives and the comparison opens with them', (
    t,
  ) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tool = (await container
        .read(contentRepositoryProvider)
        .toolById('t-1'))!;
    String? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCompareSheet(context, tool),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/compare',
          builder: (_, s) {
            opened = s.uri.toString();
            return const Scaffold(body: Text('compare'));
          },
        ),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: LizTheme.app(), routerConfig: router),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Choose a tool to compare'), findsOneWidget);

    final boxes = find.byType(Checkbox);
    expect(boxes, findsWidgets);
    await t.tap(boxes.at(0));
    await t.tap(boxes.at(1));
    await t.pumpAndSettle();
    expect(find.text('Compare 3 tools'), findsOneWidget);
    // Two is the limit beside the tool itself.
    final third = t.widget<CheckboxListTile>(
      find.byType(CheckboxListTile).at(2),
    );
    expect(third.onChanged, isNull);

    await t.tap(find.text('Compare 3 tools'));
    await t.pumpAndSettle();
    expect(opened, startsWith('/compare?ids=t-1,'));
    expect(opened!.split(',').length, 3);
  });
}
