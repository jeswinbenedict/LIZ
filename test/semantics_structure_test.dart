import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/models/news_item.dart';
import 'package:liz/shared/models/tool.dart';
import 'package:liz/shared/widgets/news_card.dart';
import 'package:liz/shared/widgets/page_header.dart';

/// What a screen reader is told, beyond the contrast and tap-size checks the
/// sweep runs: a news story is a link it can follow, its quick take and Share
/// are controls of their own.

final _item = NewsItem(
  id: 'n1',
  title: 'A model that reads receipts',
  url: 'https://example.com/story',
  snippet: 'What it does and why it matters.',
  aiSummary: const ['It reads receipts.', 'It is free.'],
  source: 'example',
  publishedAt: DateTime(2026, 10, 1),
  status: PublishStatus.published,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: LizTheme.app(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _pillKeyboardTests();

  testWidgets('a news story is a link, apart from its controls', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, NewsCard(item: _item));

    final link = tester.getSemantics(find.text(_item.title));
    expect(link.flagsCollection.isLink, isTrue);
    expect(link.linkUrl, Uri.parse(_item.url));
    expect(link.label, contains(_item.snippet));

    final quickTake = tester.getSemantics(find.text('Quick take'));
    expect(quickTake.flagsCollection.isButton, isTrue);
    expect(quickTake.label, isNot(contains(_item.title)));

    final share = tester.getSemantics(find.byTooltip('Share'));
    expect(share.label, isNot(contains(_item.title)));
    handle.dispose();
  });
}

/// A filter pill was a bare GestureDetector: the keyboard could not reach it.
void _pillKeyboardTests() {
  testWidgets('a filter pill takes focus by Tab and is pressed by Enter', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      LizFilterPill(label: 'Agents', selected: false, onTap: () => taps++),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(focused!.context, isNotNull);
    expect(
      find.ancestor(
        of: find.text('Agents'),
        matching: find.byWidgetPredicate((w) => w is FocusableActionDetector),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('a filter pill is one node: its label and its focus action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      Row(
        children: [
          LizFilterPill(label: 'All', selected: true, onTap: () {}),
          LizFilterPill(label: 'Free', selected: false, onTap: () {}),
        ],
      ),
    );
    final free = tester.getSemantics(find.text('Free'));
    expect(free.label, 'Free');
    expect(free.flagsCollection.isButton, isTrue);
    expect(free.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    handle.dispose();
  });
}
