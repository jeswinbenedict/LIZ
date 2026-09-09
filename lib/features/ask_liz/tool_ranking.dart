import '../../shared/models/tool.dart';

/// On-device ranking used when the semantic-search backend is unreachable.
///
/// Kept apart from the screen so the rules that decide what counts as an answer
/// can be exercised directly. The guiding principle is that a tool has to match
/// on *what it does*: being free or trending orders the results that already
/// qualify, and can never put a tool in front of someone on its own.
class ToolRanking {
  const ToolRanking._();

  /// Words that appear in almost any request for a tool. Overlap on these says
  /// nothing about whether the tool does what was asked for.
  static const genericTerms = {
    'free', 'paid', 'cheap', 'best', 'good', 'great', 'tool', 'tools', 'app',
    'apps', 'software', 'online', 'website', 'need', 'want', 'find', 'looking',
    'help', 'something', 'anything', 'that', 'this', 'with', 'for', 'and',
    'the', 'you', 'your', 'can', 'from', 'use', 'using', 'make', 'get',
  };

  static Set<String> termsOf(String query) =>
      query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

  static String haystack(Tool t) =>
      '${t.name} ${t.tagline} ${t.description} ${t.tags.join(' ')} ${t.category}'
          .toLowerCase();

  /// Overlap on terms that actually describe the job to be done.
  static int topicScore(Tool tool, Set<String> terms) {
    final hay = haystack(tool);
    var score = 0;
    for (final term in terms) {
      if (term.length < 3 || genericTerms.contains(term)) continue;
      if (hay.contains(term)) score += 2;
    }
    return score;
  }

  /// Topic score plus tiebreakers, used only to order tools that already match.
  static int rank(Tool tool, Set<String> terms) {
    var score = topicScore(tool, terms);
    if (terms.contains('free') && tool.pricingType.name == 'free') score += 3;
    score += (tool.trendScore / 40).round();
    return score;
  }

  /// The tools worth showing, best first. Anything with no topical overlap is
  /// dropped rather than padded in behind the ones that do match.
  static List<Tool> shortlist(List<Tool> pool, Set<String> terms,
      {int limit = 5}) {
    final matching = pool.where((t) => topicScore(t, terms) > 0).toList()
      ..sort((a, b) => rank(b, terms).compareTo(rank(a, terms)));
    return matching.take(limit).toList();
  }

  /// States what the match is based on, naming the term it hit, so a weak match
  /// reads as a weak match instead of a confident one.
  static String reasonFor(Tool tool, Set<String> terms) {
    final hay = haystack(tool);
    final matched = terms.firstWhere(
      (term) =>
          term.length > 2 && !genericTerms.contains(term) && hay.contains(term),
      orElse: () => '',
    );
    final free = terms.contains('free') && tool.pricingType.name == 'free';
    final prefix = free ? 'Free. ' : '';
    return '${prefix}Matches "$matched" — ${tool.tagline}';
  }
}
