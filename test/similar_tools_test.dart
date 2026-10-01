import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/tool_detail/similar_tools.dart';
import 'package:liz/features/tool_detail/tool_detail_screen.dart';

/// The strip is an aside on a page that is complete without it, so the rules
/// are: never show the tool you are already looking at, and show nothing
/// rather than filler.

void main() {
  test('a tool is never its own neighbour', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final similar = await container
        .read(contentRepositoryProvider)
        .similarTools('t-1');

    expect(similar.any((t) => t.id == 't-1'), isFalse);
  });

  test('an unknown tool has no neighbours rather than throwing', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final similar = await container
        .read(contentRepositoryProvider)
        .similarTools('does-not-exist');

    expect(similar, isEmpty);
  });

  testWidgets('the strip is absent when nothing is close', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.app(),
          home: const SimilarToolsSection(toolId: 'does-not-exist'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Not a heading over an empty row, and not an apology — nothing at all.
    expect(find.text('Similar tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tool page offers somewhere to go next', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.app(),
          home: const ToolDetailScreen(toolId: 't-1'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The section sits below the summary and description, and the page builds
    // lazily, so it has to be scrolled to before it exists.
    await tester.scrollUntilVisible(
      find.text('Similar tools'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Similar tools'), findsOneWidget);
    // And it leads somewhere: the strip carries real neighbours.
    expect(find.text('Coversmith'), findsOneWidget);
  });
}
