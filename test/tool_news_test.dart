import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/tool_detail/tool_news.dart';

/// News is linked to a tool only when the headline names it, and the section
/// is absent rather than empty when nothing does.

void main() {
  test('a headline naming the tool is linked to it', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final news = await c.read(contentRepositoryProvider).newsForTool('t-1');
    expect(news.map((n) => n.id), contains('n-0'));
    expect(news.every((n) => n.title.contains('Scriptly')), isTrue);
  });

  test('an unknown tool has no news rather than throwing', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
      await c.read(contentRepositoryProvider).newsForTool('nope'),
      isEmpty,
    );
  });

  Future<void> pump(WidgetTester tester, String toolId) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.app(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ToolNewsSection(toolId: toolId, name: 'Scriptly'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('the section lists the headlines', (tester) async {
    await pump(tester, 't-1');
    expect(find.text('In the news'), findsOneWidget);
    expect(find.textContaining('storyboard view'), findsOneWidget);
  });

  testWidgets('the section is absent when no headline names the tool', (
    tester,
  ) async {
    await pump(tester, 'nope');
    expect(find.text('In the news'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
