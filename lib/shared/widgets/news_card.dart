import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../models/news_item.dart';
import 'badges.dart';
import 'time_ago.dart';

/// A tech-news article card. Tapping the card or "Read" opens the original
/// source (Liz shows snippet + link out only — never republishes full text).
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});
  final NewsItem item;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: _open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Decorative: the headline directly below carries the meaning, so
            // announcing the press photo as well only adds noise.
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(LizRadius.lg),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: Env.proxiedImage(item.imageUrl!),
                    height: 168,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    // Press photos arrive at full editorial resolution — a
                    // quarter-megabyte JPEG decoded for a 168-pixel strip.
                    memCacheHeight: 336,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    placeholder: (_, __) => Container(
                      height: 168,
                      color: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(LizSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.source != null)
                        LizPill(
                          label: item.source!.toUpperCase(),
                          color: LizColors.brand,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo(item.publishedAt),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (item.snippet.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.snippet,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (item.aiSummary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(LizRadius.sm),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Quick take',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (final b in item.aiSummary.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '•  ',
                                    style: TextStyle(height: 1.3),
                                  ),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _open,
                        icon: const Icon(Icons.article_outlined, size: 18),
                        label: const Text('Read'),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.ios_share, size: 18),
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: '${item.title}\n${item.url}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
