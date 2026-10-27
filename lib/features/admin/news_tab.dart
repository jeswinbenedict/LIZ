import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/news_item.dart';
import '../../shared/models/tool.dart' show PublishStatus;
import '../../shared/widgets/states.dart';
import '../../shared/widgets/news_card.dart' show newsSourceLabel;
import '../../shared/widgets/time_ago.dart';
import 'admin_widgets.dart';

final adminNewsProvider = FutureProvider.autoDispose<List<NewsItem>>(
  (ref) => ref.watch(adminRepositoryProvider).allNews(),
);

/// The newest articles, with a way to take one down.
///
/// The feed is scraped from eight sources on a schedule. Most of what arrives
/// is fine; now and then something should not be on the page — a mis-tagged
/// press release, a broken scrape, a story that has been retracted. Until this
/// existed the repository could list articles for moderation but nothing
/// could act on them, so the only way to remove one was the database console.
class NewsTab extends ConsumerWidget {
  const NewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(adminNewsProvider);

    return news.when(
      loading: () => const LoadingView(),
      error: (_, _) =>
          ErrorView(onRetry: () => ref.invalidate(adminNewsProvider)),
      data: (items) => items.isEmpty
          ? const EmptyView(
              icon: Icons.newspaper_outlined,
              title: 'No articles yet',
              message: 'The feed fills as the hourly pull runs.',
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminNewsProvider),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  LizSpacing.gutter(MediaQuery.sizeOf(context).width),
                  0,
                  LizSpacing.gutter(MediaQuery.sizeOf(context).width),
                  48,
                ),
                children: [
                  AdminSection(
                    top: 24,
                    title: 'Articles',
                    description:
                        '${items.length} newest first. Hiding takes one off '
                        'the news feed; it can be restored.',
                    child: AdminPanel(
                      children: [
                        for (final item in items) _ArticleRow(item: item),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ArticleRow extends ConsumerWidget {
  const _ArticleRow({required this.item});
  final NewsItem item;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    PublishStatus status,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(adminRepositoryProvider).setNewsStatus(item.id, status);
    ref.invalidate(adminNewsProvider);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            status == PublishStatus.hidden
                ? 'Hidden from the news feed'
                : 'Back in the news feed',
          ),
          action: SnackBarAction(
            // A moderation click is easy to misfire on a long list, so the
            // way back is one tap rather than a scroll to find the row again.
            label: 'Undo',
            onPressed: () => ref
                .read(adminRepositoryProvider)
                .setNewsStatus(item.id, item.status)
                .then((_) => ref.invalidate(adminNewsProvider)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final hidden = item.status == PublishStatus.hidden;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.callout.copyWith(
                    color: hidden ? p.textSecondary : p.textPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: hidden ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${newsSourceLabel(item.source)} · '
                        '${timeAgo(item.publishedAt)} ago',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.footnote.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    if (hidden) ...[
                      const SizedBox(width: 10),
                      const AdminStatusLabel(
                        AdminStatus.neutral,
                        label: 'Hidden',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          hidden
              ? OutlinedButton(
                  onPressed: () => _set(context, ref, PublishStatus.published),
                  child: const Text('Restore'),
                )
              : OutlinedButton(
                  onPressed: () => _set(context, ref, PublishStatus.hidden),
                  child: const Text('Hide'),
                ),
        ],
      ),
    );
  }
}
