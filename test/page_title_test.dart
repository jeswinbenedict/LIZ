import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/shared/widgets/page_title.dart';

/// A tool page is titled the same before the app loads (the prerendered HTML,
/// liz_scraper.prerender) and after, because search engines read the title
/// once the script has run. These strings are the ones
/// scrapers/tests/test_prerender.py expects from the Python side.

void main() {
  test('a short title is kept whole', () {
    expect(
      PageTitle.forTool('Koi.rest', 'Watch some fish and regain your balance'),
      'Koi.rest — Watch some fish and regain your balance | Liz',
    );
    expect(PageTitle.forTool('Solo', ''), 'Solo | Liz');
  });

  test('a long one is cut at a word, as the prerenderer cuts it', () {
    final title = PageTitle.forTool(
      'Delightful Cells',
      'Reliable AI batch processing for spreadsheets, with retries and '
          'progress you can watch',
    );
    expect(
      title,
      'Delightful Cells — Reliable AI batch processing for spreadsheets,… | Liz',
    );
  });

  testWidgets('the default title comes back when the page closes', (t) async {
    final labels = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
          labels.add((call.arguments as Map)['label'] as String);
        }
        return null;
      },
    );
    await t.pumpWidget(
      const PageTitle(title: 'Koi.rest | Liz', child: SizedBox()),
    );
    await t.pumpWidget(const SizedBox());
    expect(labels, ['Koi.rest | Liz', PageTitle.defaultTitle]);
  });
}
