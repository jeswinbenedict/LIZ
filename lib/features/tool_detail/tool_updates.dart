import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets/time_ago.dart';

/// One product update / release / new-feature item for a tool.
class ToolUpdate {
  const ToolUpdate({
    required this.title,
    required this.url,
    required this.source,
    this.note,
    this.publishedAt,
  });

  final String title;
  final String? note;
  final String url;
  final String source;
  final DateTime? publishedAt;

  factory ToolUpdate.fromJson(Map<String, dynamic> j) => ToolUpdate(
        title: (j['title'] ?? '').toString(),
        note: (j['note'] == null || j['note'].toString().isEmpty)
            ? null
            : j['note'].toString(),
        url: (j['url'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        publishedAt: j['published_at'] == null
            ? null
            : DateTime.tryParse(j['published_at'].toString()),
      );
}

/// Identifies which tool to fetch updates for (name + repo hints).
typedef ToolUpdateKey = (String name, String? sourceUrl, String slug);

/// Live "what's new" for a tool — GitHub Releases when it has a public repo,
/// else feature-announcement fallback. autoDispose = fresh on each visit.
final toolUpdatesProvider = FutureProvider.autoDispose
    .family<List<ToolUpdate>, ToolUpdateKey>((ref, key) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null || key.$1.trim().isEmpty) return const [];
  final res = await client.functions.invoke('tool-updates', body: {
    'name': key.$1,
    'source_url': key.$2,
    'slug': key.$3,
  });
  final payload = res.data;
  if (payload is! Map || payload['data'] is! List) return const [];
  return (payload['data'] as List)
      .whereType<Map>()
      .map((e) => ToolUpdate.fromJson(e.cast<String, dynamic>()))
      .where((u) => u.title.isNotEmpty && u.url.isNotEmpty)
      .toList();
});

/// "What's new" section shown on every tool detail page — live per visit.
class ToolUpdatesSection extends ConsumerWidget {
  const ToolUpdatesSection({
    super.key,
    required this.name,
    required this.slug,
    this.sourceUrl,
  });

  final String name;
  final String slug;
  final String? sourceUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No backend in demo/mock mode → hide the section entirely.
    if (ref.watch(supabaseClientProvider) == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final key = (name, sourceUrl, slug);
    final async = ref.watch(toolUpdatesProvider(key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.new_releases_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text("What's new", style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => ref.invalidate(toolUpdatesProvider(key)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (_, __) => _Hint(
            text: "Couldn't load updates right now.",
            onRetry: () => ref.invalidate(toolUpdatesProvider(key)),
          ),
          data: (items) => items.isEmpty
              ? const _Hint(text: 'No recent updates found for this tool.')
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _UpdateRow(item: items[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.item});
  final ToolUpdate item;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRelease = item.source == 'GitHub Releases';
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(LizRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isRelease ? Icons.rocket_launch_outlined : Icons.campaign_outlined,
                size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
                  if (item.note != null) ...[
                    const SizedBox(height: 2),
                    Text(item.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.3)),
                  ],
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
          Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
