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
          action: SectionAction(
            label: 'All news',
            onPressed: () => context.go('/news'),
          ),
        ),
        // One framed list, like the table above it: a story per row.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: context.liz.surface,
              shape: LizRadius.shape(
                LizRadius.md,
                side: BorderSide(color: context.liz.hairline),
              ),
            ),
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(LizRadius.md),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.liz.hairline),
                    _HeadlineRow(headline: items[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One story: where and when, the headline, and the tools it names. Wide:
/// the tools sit at the end of the row; narrow: under the headline.
class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({required this.headline});
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
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final story = Semantics(
      link: true,
      linkUrl: Uri.tryParse(item.url),
      label: '${item.title}, from ${item.source ?? 'the news'}',
      container: true,
      child: InkWell(
        onTap: _open,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$source · ${timeAgo(item.publishedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.footnote.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.headline.copyWith(color: p.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.north_east,
                    size: 16,
                    color: p.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final tools = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final t in headline.tools.take(3))
          ActionChip(
            tooltip: 'Open ${t.name}',
            avatar: Icon(Icons.arrow_forward, size: 14, color: p.textSecondary),
            label: Text(t.name),
            onPressed: () => context.push(
              t.slug.isEmpty
                  ? '/tool/${t.id}'
                  : '/tools/${Uri.encodeComponent(t.slug)}',
            ),
          ),
      ],
    );

    if (wide) {
      return Row(
        children: [
          Expanded(child: story),
          Padding(padding: const EdgeInsets.only(right: 12), child: tools),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        story,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: tools,
        ),
      ],
    );
  }
}
