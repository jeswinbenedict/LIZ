import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/top_bar.dart';
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
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final phone = context.isPhone;

    return Scaffold(
      appBar: const LizTopBar(title: 'Community', titleIsHeading: false),
      body: MaxWidth(
        maxWidth: 720 + gutter * 2,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(postFeedProvider(key));
            await ref.read(postFeedProvider(key).future);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  title: 'Community',
                  subtitle: phone
                      ? null
                      : 'What people are doing with the tools Liz lists.',
                  // The page's one primary action, where it is seen first —
                  // it used to float over the last post.
                  trailing: FilledButton.icon(
                    onPressed: () => showPostComposer(context, ref),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('New post'),
                  ),
                  bottom: 16,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LizSegmented<bool>(
                      segments: const {false: 'Newest', true: 'Trending'},
                      value: _trending,
                      onChanged: (v) => setState(() => _trending = v),
                    ),
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
                        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
                        sliver: SliverList.separated(
                          itemCount: posts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) => PostCard(post: posts[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
