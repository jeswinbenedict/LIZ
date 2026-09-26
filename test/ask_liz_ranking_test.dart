import 'package:flutter_test/flutter_test.dart';
import 'package:liz/features/ask_liz/tool_ranking.dart';
import 'package:liz/shared/models/tool.dart';

/// These cases are drawn from real failures. Asking for a background remover
/// returned a Claude Code helper and a RAG pipeline builder, each captioned
/// "Free, and matches what you described", because being free and trending was
/// treated as evidence of a fit. The rules below are what stops that.

Tool _tool({
  required String id,
  required String name,
  String tagline = '',
  String description = '',
  List<String> tags = const [],
  String category = 'new-apps',
  PricingType pricing = PricingType.unknown,
  double trendScore = 0,
}) {
  return Tool(
    id: id,
    name: name,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    tagline: tagline,
    description: description,
    aiSummary: const [],
    websiteUrl: 'https://example.com',
    logoUrl: null,
    category: category,
    tags: tags,
    platforms: const ['web'],
    pricingType: pricing,
    priceNote: null,
    source: 'test',
    sourceUrl: null,
    launchedAt: null,
    trendScore: trendScore,
    viewCount: 0,
    saveCount: 0,
    avgRating: 0,
    ratingCount: 0,
    status: PublishStatus.published,
    createdAt: DateTime(2026, 1, 1),
    trendRank: null,
  );
}

final _backgroundRemover = _tool(
  id: '1',
  name: 'Cutout',
  tagline: 'Remove image backgrounds in one click.',
  description: 'Removes the background from any image.',
  tags: ['image'],
  category: 'ai-image',
);

// The two that used to win the query, purely for being free and trending.
final _codeHelper = _tool(
  id: '2',
  name: 'cc-switch',
  tagline: 'A cross-platform desktop assistant for Claude Code.',
  description: 'Switch between coding agents.',
  tags: ['ai-tools'],
  category: 'ai-dev',
  pricing: PricingType.free,
  trendScore: 100,
);

final _ragBuilder = _tool(
  id: '3',
  name: 'dify',
  tagline: 'Build agentic workflows and RAG pipelines.',
  description: 'LLM app development platform.',
  tags: ['agent'],
  category: 'ai-agents',
  pricing: PricingType.free,
  trendScore: 95,
);

void main() {
  group('topicScore', () {
    test('counts only terms describing the job to be done', () {
      final terms = ToolRanking.termsOf('remove image backgrounds');
      expect(ToolRanking.topicScore(_backgroundRemover, terms), greaterThan(0));
    });

    test('ignores generic words, so "free tool" alone is not a match', () {
      final terms = ToolRanking.termsOf('free tool app software');
      expect(ToolRanking.topicScore(_codeHelper, terms), 0);
      expect(ToolRanking.topicScore(_ragBuilder, terms), 0);
    });

    test('ignores words shorter than three characters', () {
      expect(ToolRanking.topicScore(_backgroundRemover, {'an', 'to', 'my'}), 0);
    });
  });

  group('shortlist', () {
    test('drops tools with no topical overlap however free or trending', () {
      final terms = ToolRanking.termsOf(
        'free AI tool to remove image backgrounds',
      );
      final result = ToolRanking.shortlist([
        _codeHelper,
        _ragBuilder,
        _backgroundRemover,
      ], terms);

      expect(
        result.map((t) => t.name),
        ['Cutout'],
        reason: 'a Claude Code helper is not an answer to a background remover',
      );
    });

    test('returns nothing when the catalog cannot answer the question', () {
      final terms = ToolRanking.termsOf('review my pull requests');
      expect(ToolRanking.shortlist([_backgroundRemover], terms), isEmpty);
    });

    test('orders qualifying tools by relevance before popularity', () {
      final weakButTrending = _tool(
        id: '4',
        name: 'Trendy',
        tagline: 'Something about images.',
        tags: ['image'],
        trendScore: 100,
      );
      final terms = ToolRanking.termsOf('remove image backgrounds');
      final result = ToolRanking.shortlist([
        weakButTrending,
        _backgroundRemover,
      ], terms);

      expect(result.first.name, 'Cutout');
    });

    test('honours the limit', () {
      final many = List.generate(
        10,
        (i) => _tool(id: '$i', name: 'Tool $i', tagline: 'image editing'),
      );
      expect(
        ToolRanking.shortlist(many, ToolRanking.termsOf('image')).length,
        5,
      );
    });
  });

  group('reasonFor', () {
    test('names the term it matched rather than claiming a general fit', () {
      final terms = ToolRanking.termsOf('remove image backgrounds');
      final reason = ToolRanking.reasonFor(_backgroundRemover, terms);

      expect(reason, contains('image'));
      expect(reason, contains(_backgroundRemover.tagline));
      expect(reason, isNot(contains('matches what you described')));
    });

    test('mentions free only as an aside, never as the reason', () {
      final freeMatch = _tool(
        id: '5',
        name: 'FreeCut',
        tagline: 'Background removal.',
        tags: ['background'],
        pricing: PricingType.free,
      );
      final reason = ToolRanking.reasonFor(
        freeMatch,
        ToolRanking.termsOf('free background remover'),
      );

      expect(reason, startsWith('Free. '));
      expect(reason, contains('background'));
    });
  });

  group('when the server refuses', () {
    test('a rate limit is worth saying out loud', () {
      // ask-liz is capped at 30 questions an hour per address. Silently
      // falling through to keyword ranking would hand back visibly worse
      // answers and blame nothing — the failure this screen was rebuilt to
      // remove — so this one gets a message.
      final notice = noticeForStatus(429);
      expect(notice, isNotNull);
      expect(notice, contains('few minutes'));
    });

    test('everything else falls back quietly', () {
      // "The backend is unavailable" helps nobody who just wants an answer,
      // and the on-device ranking can give them one.
      for (final status in [null, 400, 401, 500, 502, 503]) {
        expect(noticeForStatus(status), isNull, reason: 'status $status');
      }
    });
  });
}
