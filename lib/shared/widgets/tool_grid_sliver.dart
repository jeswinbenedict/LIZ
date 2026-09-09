import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../features/discover/discover_controller.dart';
import 'skeletons.dart';
import 'states.dart';
import 'tool_card.dart';

/// A responsive, infinite-scrolling grid of tool cards driven by a [FeedKey].
/// Cross-axis count adapts to width (1 → 4 columns).
class ToolGridSliver extends ConsumerWidget {
  const ToolGridSliver({super.key, required this.feedKey});
  final FeedKey feedKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(toolFeedProvider(feedKey));
    final width = MediaQuery.sizeOf(context).width;
    final columns = gridColumnsFor(width);

    if (state.loading) {
      return const ToolGridSkeletonSliver();
    }
    if (state.error != null && state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: ErrorView(
          onRetry: () => ref.read(toolFeedProvider(feedKey).notifier).refresh(),
        ),
      );
    }
    if (state.items.isEmpty) {
      return const SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.search_off,
          title: 'No tools here yet',
          message: 'Try a different category or filter.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: toolCardExtent(context),
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          // Trigger load-more as the user nears the end.
          if (index >= state.items.length - columns) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(toolFeedProvider(feedKey).notifier).loadMore();
            });
          }
          return ToolCard(tool: state.items[index]);
        }, childCount: state.items.length),
      ),
    );
  }
}

/// A thin footer showing the load-more spinner.
class LoadMoreFooter extends ConsumerWidget {
  const LoadMoreFooter({super.key, required this.feedKey});
  final FeedKey feedKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingMore = ref.watch(
      toolFeedProvider(feedKey).select((s) => s.loadingMore),
    );
    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: loadingMore
            ? const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
