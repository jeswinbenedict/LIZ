import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/models/tool.dart';
import 'package:liz/shared/widgets/tool_logo.dart';

/// An empty logo_url is the logo job saying it looked and found nothing
/// usable. Asking the proxy again only logged a 404 in every visitor's
/// console, for the same letter tile.

Tool _tool(String? logoUrl) => Tool(
  id: 't1',
  name: 'Echo',
  slug: 'echo',
  tagline: '',
  description: '',
  aiSummary: const [],
  websiteUrl: 'https://echo.example',
  logoUrl: logoUrl,
  category: 'new-apps',
  tags: const [],
  platforms: const ['web'],
  pricingType: PricingType.unknown,
  priceNote: null,
  source: 'test',
  sourceUrl: null,
  launchedAt: null,
  trendScore: 0,
  viewCount: 0,
  saveCount: 0,
  avgRating: 0,
  ratingCount: 0,
  status: PublishStatus.published,
  createdAt: DateTime(2026, 1, 1),
  trendRank: null,
);

Future<void> _pump(WidgetTester tester, Tool tool) => tester.pumpWidget(
  MaterialApp(
    theme: LizTheme.app(),
    home: Scaffold(body: ToolLogo(tool: tool)),
  ),
);

void main() {
  testWidgets('a tool marked as having no logo draws its letter, unasked', (
    tester,
  ) async {
    await _pump(tester, _tool(''));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('a stored logo is still loaded', (tester) async {
    await _pump(
      tester,
      _tool('https://x.supabase.co/storage/v1/object/public/logos/t1.webp'),
    );
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
