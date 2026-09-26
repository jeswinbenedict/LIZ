import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/news_item.dart';
import '../../shared/models/tool.dart' show PublishStatus;
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';

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
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ArticleRow(item: items[i]),
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
    final scheme = Theme.of(context).colorScheme;
    final hidden = item.status == PublishStatus.hidden;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: LizSpacing.md),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          decoration: hidden ? TextDecoration.lineThrough : null,
          color: hidden ? scheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        '${item.source ?? 'unknown source'} · ${timeAgo(item.publishedAt)}'
        '${hidden ? ' · hidden' : ''}',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: hidden
          ? TextButton(
              onPressed: () => _set(context, ref, PublishStatus.published),
              child: const Text('Restore'),
            )
          : TextButton(
              onPressed: () => _set(context, ref, PublishStatus.hidden),
              child: const Text('Hide'),
            ),
    );
  }
}
