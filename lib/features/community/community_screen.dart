import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../shared/widgets/states.dart';
import 'community_controller.dart';
import 'community_widgets.dart';
import 'composers.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _trending = false;

  @override
  Widget build(BuildContext context) {
    final key = PostFeedKey(trending: _trending);
    final feed = ref.watch(postFeedProvider(key));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPostComposer(context, ref),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Post'),
      ),
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 720,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(postFeedProvider(key));
              await ref.read(postFeedProvider(key).future);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  titleSpacing: 20,
                  title: context.isPhone
                      ? const LizWordmark()
                      : Text(
                          'Community',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Newest'),
                          icon: Icon(Icons.schedule),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Trending'),
                          icon: Icon(Icons.trending_up),
                        ),
                      ],
                      selected: {_trending},
                      onSelectionChanged: (s) =>
                          setState(() => _trending = s.first),
                    ),
                  ),
                ),
                feed.when(
                  loading: () => const SliverToBoxAdapter(child: LoadingView()),
                  error: (_, _) => SliverToBoxAdapter(
                    child: ErrorView(
                      onRetry: () => ref.invalidate(postFeedProvider(key)),
                    ),
                  ),
                  data: (posts) => posts.isEmpty
                      ? SliverToBoxAdapter(
                          child: EmptyView(
                            icon: Icons.forum_outlined,
                            title: 'Start the conversation',
                            message: 'Share a tool you discovered.',
                            action: FilledButton.icon(
                              onPressed: () => showPostComposer(context, ref),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Create a post'),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          sliver: SliverList.separated(
                            itemCount: posts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                PostCard(post: posts[i]),
                          ),
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
