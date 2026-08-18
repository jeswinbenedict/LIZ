import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets/time_ago.dart';

/// One headline about a tool, from the live tool-news aggregator.
class ToolNewsItem {
  const ToolNewsItem({
    required this.title,
    required this.url,
    required this.source,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String source;
  final DateTime? publishedAt;

  factory ToolNewsItem.fromJson(Map<String, dynamic> j) => ToolNewsItem(
        title: (j['title'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        publishedAt: j['published_at'] == null
            ? null
            : DateTime.tryParse(j['published_at'].toString()),
      );
}

/// Live, real-time news for a tool (Google News + Hacker News via the
/// `tool-news` Edge Function). autoDispose so each visit fetches fresh results.
final toolNewsProvider =
    FutureProvider.autoDispose.family<List<ToolNewsItem>, String>((ref, query) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null || query.trim().isEmpty) return const [];
  final res = await client.functions
      .invoke('tool-news', body: {'query': query});
  final payload = res.data;
  if (payload is! Map || payload['data'] is! List) return const [];
  return (payload['data'] as List)
      .whereType<Map>()
      .map((e) => ToolNewsItem.fromJson(e.cast<String, dynamic>()))
      .where((n) => n.title.isNotEmpty && n.url.isNotEmpty)
      .toList();
});

/// "Latest news" section shown on every tool detail page. Live per visit, with
/// loading / empty / error states so it always renders cleanly.
class ToolNewsSection extends ConsumerWidget {
  const ToolNewsSection({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final newsAsync = ref.watch(toolNewsProvider(query));

    // Hide the whole section in demo/mock mode (no backend to query).
    if (ref.watch(supabaseClientProvider) == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('Latest news', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => ref.invalidate(toolNewsProvider(query)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        newsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, __) => _Hint(
            text: "Couldn't load news right now.",
            onRetry: () => ref.invalidate(toolNewsProvider(query)),
          ),
          data: (items) => items.isEmpty
              ? const _Hint(text: 'No recent news found for this tool.')
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _NewsRow(item: items[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});
  final ToolNewsItem item;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(LizRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(
                    item.publishedAt != null
                        ? '${item.source} · ${timeAgo(item.publishedAt!)}'
                        : item.source,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
