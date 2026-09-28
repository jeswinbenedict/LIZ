import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../models/news_item.dart';
import 'time_ago.dart';

/// A news source as a reader would write it: `techcrunch` → "TechCrunch".
String newsSourceLabel(String? source) {
  const known = {
    'hackernews': 'Hacker News',
    'techcrunch': 'TechCrunch',
    'theverge': 'The Verge',
    'arstechnica': 'Ars Technica',
    'wired': 'Wired',
    'engadget': 'Engadget',
    'techreview': 'MIT Technology Review',
    'devto': 'DEV',
  };
  if (source == null || source.isEmpty) return 'News';
  return known[source] ?? source[0].toUpperCase() + source.substring(1);
}

/// One article in the news list (docs/DESIGN.md §8, News): an editorial row
/// — source and time as an eyebrow, the headline, two lines of summary, and
/// the image beside it on wide screens or above it on phones. The AI "quick
/// take" folds away so the list can be scanned; it used to be a tinted box
/// inside every card, which tripled the height of the feed.
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
    final p = context.liz;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    newsSourceLabel(item.source),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.footnote.copyWith(
                      color: LizColors.legibleOn(p.accent, p.canvas),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '  ·  ${timeAgo(item.publishedAt)}',
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              style: LizText.title3.copyWith(color: p.textPrimary),
            ),
            if (item.snippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LizText.callout.copyWith(color: p.textSecondary),
              ),
            ],
          ],
        );

        final image = hasImage
            ? ExcludeSemantics(
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(LizRadius.sm),
                  child: CachedNetworkImage(
                    imageUrl: Env.proxiedImage(item.imageUrl!),
                    width: wide ? 168 : double.infinity,
                    height: wide ? 112 : 180,
                    fit: BoxFit.cover,
                    memCacheHeight: 360,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                    placeholder: (_, _) => Container(
                      width: wide ? 168 : double.infinity,
                      height: wide ? 112 : 180,
                      color: p.surfaceMuted,
                    ),
                  ),
                ),
              )
            : null;

        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _open,
            customBorder: LizRadius.shape(LizRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: text),
                        if (image != null) ...[
                          const SizedBox(width: 20),
                          image,
                        ],
                      ],
                    )
                  else ...[
                    if (image != null) ...[image, const SizedBox(height: 14)],
                    text,
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (item.aiSummary.isNotEmpty)
                        Expanded(child: _QuickTake(bullets: item.aiSummary))
                      else
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
          ),
        );
      },
    );
  }
}

/// The AI summary of an article, folded until asked for.
class _QuickTake extends StatefulWidget {
  const _QuickTake({required this.bullets});
  final List<String> bullets;

  @override
  State<_QuickTake> createState() => _QuickTakeState();
}

class _QuickTakeState extends State<_QuickTake> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final duration = LizMotion.of(context, LizMotion.standard);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 40),
            ),
            onPressed: () => setState(() => _open = !_open),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Quick take'),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: duration,
                  child: const Icon(Icons.expand_more, size: 18),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: LizMotion.ease,
          alignment: Alignment.topLeft,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in widget.bullets.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(
                                  top: 8,
                                  right: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: p.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  b,
                                  style: LizText.callout.copyWith(
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
