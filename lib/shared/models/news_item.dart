import 'json.dart';
import 'tool.dart' show PublishStatus;

/// A headline / article — support content, always links out (no full republish).
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.url,
    required this.snippet,
    required this.aiSummary,
    this.imageUrl,
    this.source,
    this.category,
    required this.publishedAt,
    required this.status,
  });

  final String id;
  final String title;
  final String url;
  final String snippet;
  final List<String> aiSummary;
  final String? imageUrl;
  final String? source;
  final String? category;
  final DateTime publishedAt;
  final PublishStatus status;

  factory NewsItem.fromJson(Map<String, dynamic> j) {
    final raw = j['ai_summary'];
    final summary = raw is List
        ? raw.map((e) => e.toString()).toList()
        : (raw is Map && raw['bullets'] is List
              ? (raw['bullets'] as List).map((e) => e.toString()).toList()
              : const <String>[]);
    return NewsItem(
      id: asString(j['id']),
      title: asString(j['title']),
      url: asString(j['url']),
      snippet: asString(j['snippet']),
      aiSummary: summary,
      imageUrl: asStringOrNull(j['image_url']),
      source: asStringOrNull(j['source']),
      category: asStringOrNull(j['category']),
      publishedAt: asDate(j['published_at']),
      status: PublishStatus.parse(asStringOrNull(j['status'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'snippet': snippet,
    'ai_summary': aiSummary,
    'image_url': imageUrl,
    'source': source,
    'category': category,
    'published_at': publishedAt.toIso8601String(),
    'status': status.value,
  };

  NewsItem copyWith({PublishStatus? status}) => NewsItem(
    id: id,
    title: title,
    url: url,
    snippet: snippet,
    aiSummary: aiSummary,
    imageUrl: imageUrl,
    source: source,
    category: category,
    publishedAt: publishedAt,
    status: status ?? this.status,
  );
}
