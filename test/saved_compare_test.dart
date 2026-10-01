import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/track/saved_screen.dart';
import 'package:liz/features/track/track_controller.dart';

/// Comparing from Saved works the way selecting photos does: Select, tap two
/// or three, Compare. It replaced a checkbox drawn over every tool's logo.

void main() {
  testWidgets('Select, pick tools, and Compare appears at two', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tools = await tester.runAsync(() async {
      final c = ProviderContainer();
      final page = await c
          .read(contentRepositoryProvider)
          .tools(const ToolQuery(limit: 4));
      c.dispose();
      return page.items;
    });

    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWithValue(true),
        bookmarkedToolsProvider.overrideWith((ref) async => tools!),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: LizTheme.app(), home: const SavedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Not selecting yet: tapping a card would open the tool, and no check
    // marks are drawn.
    expect(find.text('Compare 2'), findsNothing);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Choose two or three tools to compare.'), findsOneWidget);

    await tester.tap(find.text(tools![0].name));
    await tester.pumpAndSettle();
    expect(
      find.text('Compare 2'),
      findsNothing,
      reason: 'one is not a comparison',
    );

    await tester.tap(find.text(tools[1].name));
    await tester.pumpAndSettle();
    expect(find.text('Compare 2'), findsOneWidget);

    await tester.tap(find.text(tools[2].name));
    await tester.tap(find.text(tools[3].name));
    await tester.pumpAndSettle();
    // Three is the limit, and the fourth tap says so rather than failing
    // silently.
    expect(find.text('Compare 3'), findsOneWidget);
    expect(find.textContaining('Compare up to 3'), findsOneWidget);

    // Done leaves selection mode and forgets the picks.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(container.read(compareSelectionProvider), isEmpty);
    expect(find.text('Compare 3'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
