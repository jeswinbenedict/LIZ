import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/news_card.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import 'news_controller.dart';

/// Technology News Feed — live tech headlines from RSS/API ingestion, updated
/// hourly and pushed in real time via Supabase Realtime.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(newsControllerProvider);
    final controller = ref.read(newsControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 760,
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  titleSpacing: 20,
                  title: Row(
                    children: [
                      Text(
                        'Tech News',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(width: 10),
                      if (state.live) const _LiveBadge(),
                    ],
                  ),
                ),
                if (state.loading)
                  const NewsListSkeletonSliver()
                else if (state.error != null && state.items.isEmpty)
                  SliverToBoxAdapter(
                    child: ErrorView(onRetry: controller.refresh),
                  )
                else if (state.items.isEmpty)
                  const SliverToBoxAdapter(
                    child: EmptyView(
                      icon: Icons.newspaper_outlined,
                      title: 'No news yet',
                      message:
                          'The feed fills up as the ingestion job pulls the latest tech headlines.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: state.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i >= state.items.length - 3) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => controller.loadMore(),
                          );
                        }
                        return NewsCard(item: state.items[i]);
                      },
                    ),
                  ),
                if (state.loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: LizColors.positive.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: LizColors.positive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: LizColors.positive,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
