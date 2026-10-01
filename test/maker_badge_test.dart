import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/data/mock_data.dart';
import 'package:liz/features/tool_detail/maker_badge.dart';
import 'package:liz/shared/models/tool.dart';

/// The badge snippet makers paste into their sites: it must point at the
/// files the prerenderer writes, survive a name with markup in it, and not
/// be offered when Liz has no address to link to.

void main() {
  final tool = MockData.tools.firstWhere((t) => t.id == 't-1');

  test('the snippet links the tool page and the prerendered image', () {
    final b = MakerBadge.from(tool, 'https://liz.example/')!;
    expect(b.pageUrl, 'https://liz.example/tools/${tool.slug}');
    expect(b.imageUrl, 'https://liz.example/badge/${tool.slug}.svg');
    expect(b.html, contains('width="136" height="48"'));
    expect(b.markdown, '[![${tool.name} on Liz](${b.imageUrl})](${b.pageUrl})');
    final dark = MakerBadge.from(tool, 'https://liz.example', dark: true)!;
    expect(dark.imageUrl, endsWith('/badge/${tool.slug}-dark.svg'));
  });

  test('a name cannot break out of the alt attribute', () {
    final b = MakerBadge.from(
      Tool.fromJson({...tool.toJson(), 'name': 'Evil" onerror="x'}),
      'https://liz.example',
    )!;
    expect(b.html, isNot(contains('" onerror')));
    expect(b.html, contains('Evil&quot; onerror=&quot;x on Liz'));
  });

  test('no address, no badge', () {
    expect(MakerBadge.from(tool, ''), isNull);
    expect(
      MakerBadge.from(
        Tool.fromJson({...tool.toJson(), 'slug': ''}),
        'https://x',
      ),
      isNull,
    );
  });

  testWidgets('the sheet shows a preview and both snippets', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.app(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMakerBadgeSheet(
                  context,
                  tool,
                  base: 'https://liz.example',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('A badge for ${tool.name}'), findsOneWidget);
    expect(find.byType(BadgePreview), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('Markdown (for a README)'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.textContaining('-dark.svg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
