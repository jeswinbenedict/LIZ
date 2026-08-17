import 'json.dart';

enum PricingType {
  free,
  freemium,
  paid,
  unknown;

  static PricingType parse(String? v) {
    switch (v) {
      case 'free':
        return PricingType.free;
      case 'freemium':
        return PricingType.freemium;
      case 'paid':
        return PricingType.paid;
      default:
        return PricingType.unknown;
    }
  }

  String get label => switch (this) {
        PricingType.free => 'Free',
        PricingType.freemium => 'Freemium',
        PricingType.paid => 'Paid',
        PricingType.unknown => 'Unknown',
      };
}

enum PublishStatus {
  pending,
  published,
  hidden;

  static PublishStatus parse(String? v) => switch (v) {
        'published' => PublishStatus.published,
        'hidden' => PublishStatus.hidden,
        _ => PublishStatus.pending,
      };

  String get value => name;
}

/// An app / AI tool / product — the primary unit of discovery.
class Tool {
  const Tool({
    required this.id,
    required this.name,
    required this.slug,
    required this.tagline,
    required this.description,
    required this.aiSummary,
    required this.websiteUrl,
    required this.logoUrl,
    required this.category,
    required this.tags,
    required this.platforms,
    required this.pricingType,
    required this.priceNote,
    required this.source,
    required this.sourceUrl,
    required this.launchedAt,
    required this.trendScore,
    required this.viewCount,
    required this.saveCount,
    required this.avgRating,
    required this.ratingCount,
    required this.status,
    required this.createdAt,
    this.trendRank,
  });

  final String id;
  final String name;
  final String slug;
  final String tagline;
  final String description;

  /// 3-bullet AI summary generated at ingest.
  final List<String> aiSummary;
  final String? websiteUrl;
  final String? logoUrl;
  final String category; // category slug
  final List<String> tags;
  final List<String> platforms;
  final PricingType pricingType;
  final String? priceNote;
  final String? source;
  final String? sourceUrl;
  final DateTime? launchedAt;
  final double trendScore;
  final int viewCount;
  final int saveCount;
  final double avgRating;
  final int ratingCount;
  final PublishStatus status;
  final DateTime createdAt;

  /// Unique leaderboard position (1 = top), recomputed with the trend score.
  /// Null in mock/demo mode (where the badge falls back to the raw score).
  final int? trendRank;

  bool get isNew =>
      DateTime.now().difference(createdAt).inDays <= 14;

  factory Tool.fromJson(Map<String, dynamic> j) {
    // ai_summary may arrive as a jsonb list of strings, or {"bullets": [...]}.
    final rawSummary = j['ai_summary'];
    List<String> summary;
    if (rawSummary is List) {
      summary = rawSummary.map((e) => e.toString()).toList();
    } else if (rawSummary is Map && rawSummary['bullets'] is List) {
      summary = (rawSummary['bullets'] as List).map((e) => e.toString()).toList();
    } else {
      summary = const [];
    }

    return Tool(
      id: asString(j['id']),
      name: asString(j['name']),
      slug: asString(j['slug']),
      tagline: asString(j['tagline']),
      description: asString(j['description']),
      aiSummary: summary,
      websiteUrl: asStringOrNull(j['website_url']),
      logoUrl: asStringOrNull(j['logo_url']),
      category: asString(j['category']),
      tags: asStringList(j['tags']),
      platforms: asStringList(j['platforms']),
      pricingType: PricingType.parse(asStringOrNull(j['pricing_type'])),
      priceNote: asStringOrNull(j['price_note']),
      source: asStringOrNull(j['source']),
      sourceUrl: asStringOrNull(j['source_url']),
      launchedAt: asDateOrNull(j['launched_at']),
      trendScore: asDouble(j['trend_score']),
      viewCount: asInt(j['view_count']),
      saveCount: asInt(j['save_count']),
      avgRating: asDouble(j['avg_rating']),
      ratingCount: asInt(j['rating_count']),
      status: PublishStatus.parse(asStringOrNull(j['status'])),
      createdAt: asDate(j['created_at']),
      trendRank: j['trend_rank'] == null ? null : asInt(j['trend_rank']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'tagline': tagline,
        'description': description,
        'ai_summary': aiSummary,
        'website_url': websiteUrl,
        'logo_url': logoUrl,
        'category': category,
        'tags': tags,
        'platforms': platforms,
        'pricing_type': pricingType.name,
        'price_note': priceNote,
        'source': source,
        'source_url': sourceUrl,
        'launched_at': launchedAt?.toIso8601String(),
        'trend_score': trendScore,
        'view_count': viewCount,
        'save_count': saveCount,
        'avg_rating': avgRating,
        'rating_count': ratingCount,
        'status': status.value,
        'created_at': createdAt.toIso8601String(),
        'trend_rank': trendRank,
      };

  Tool copyWith({
    int? saveCount,
    int? viewCount,
    double? avgRating,
    int? ratingCount,
    PublishStatus? status,
  }) =>
      Tool(
        id: id,
        name: name,
        slug: slug,
        tagline: tagline,
        description: description,
        aiSummary: aiSummary,
        websiteUrl: websiteUrl,
        logoUrl: logoUrl,
        category: category,
        tags: tags,
        platforms: platforms,
        pricingType: pricingType,
        priceNote: priceNote,
        source: source,
        sourceUrl: sourceUrl,
        launchedAt: launchedAt,
        trendScore: trendScore,
        viewCount: viewCount ?? this.viewCount,
        saveCount: saveCount ?? this.saveCount,
        avgRating: avgRating ?? this.avgRating,
        ratingCount: ratingCount ?? this.ratingCount,
        status: status ?? this.status,
        createdAt: createdAt,
        trendRank: trendRank,
      );
}
