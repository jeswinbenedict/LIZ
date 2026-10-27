import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/news_card.dart' show newsSourceLabel;

/// The latest headlines that name a tool in the catalog.
final toolHeadlinesProvider = FutureProvider.autoDispose<List<ToolHeadline>>(
  (ref) => ref.watch(contentRepositoryProvider).toolHeadlines(limit: 4),
);

/// "In the news" on Discover: stories about tools Liz lists, each with a way
/// to the story and a way to the tool (migrations 0052–0056 link them).
///
/// Absent while loading and when no recent headline names a tool, like the
/// other optional shelves: the page is complete without it.
class ToolHeadlines extends ConsumerWidget {
  const ToolHeadlines({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(toolHeadlinesProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Tools in the headlines',
          subtitle: 'Recent stories that name a tool Liz lists.',
          action: TextButton(
            onPressed: () => context.go('/news'),
            child: const Text('All news'),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 720 ? 2 : 1;
              final width = (box.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final h in items)
                    SizedBox(
                      width: width,
                      child: _HeadlineCard(headline: h),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.headline});
  final ToolHeadline headline;

  Future<void> _open() async {
    final uri = Uri.tryParse(headline.item.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final item = headline.item;
    final source = newsSourceLabel(item.source);
    return Material(
      color: p.surface,
      shape: LizRadius.shape(LizRadius.md, side: BorderSide(color: p.hairline)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            link: true,
            linkUrl: Uri.tryParse(item.url),
            label: '${item.title}, from ${item.source ?? 'the news'}',
            container: true,
            child: InkWell(
              onTap: _open,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$source · ${timeAgo(item.publishedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LizText.label.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.north_east,
                            size: 15,
                            color: p.textTertiary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.headline.copyWith(
                          color: p.textPrimary,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in headline.tools.take(3))
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => context.push(
                      t.slug.isEmpty
                          ? '/tool/${t.id}'
                          : '/tools/${Uri.encodeComponent(t.slug)}',
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 15),
                    label: Text(t.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
