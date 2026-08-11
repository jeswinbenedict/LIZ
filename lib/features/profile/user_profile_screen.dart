import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/user_avatar.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../track/follow_user_button.dart';

/// Public profile for any user: bio, their reviews + posts, and a follow button.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileByIdProvider(userId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/community');
          }
        }),
        title: const Text('Profile'),
      ),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (_, __) =>
            ErrorView(onRetry: () => ref.invalidate(profileByIdProvider(userId))),
        data: (profile) => profile == null
            ? const EmptyView(
                icon: Icons.person_off_outlined,
                title: 'User not found',
                message: 'This profile may have been removed.')
            : _Body(profile: profile),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(currentUserProvider);
    final isSelf = me?.id == profile.id;
    final reviews = ref.watch(reviewsByUserProvider(profile.id));
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));

    return MaxWidth(
      maxWidth: 720,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(profile: profile, radius: 34),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(profile.displayName,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                              ),
                              if (profile.role.canModerate) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.verified,
                                    size: 18, color: scheme.primary),
                              ],
                            ],
                          ),
                          Text('@${profile.username}',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (!isSelf) FollowUserButton(userId: profile.id),
                  ],
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(profile.bio!, style: const TextStyle(height: 1.4)),
                ],
                const SizedBox(height: 12),
                Text('Joined ${timeAgo(profile.createdAt)} ago',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12.5)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Reviews',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          reviews.when(
            loading: () => const LoadingView(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('No reviews yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : Column(
                    children: [
                      for (final r in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ReviewTile(review: r),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child:
                Text('Posts', style: Theme.of(context).textTheme.titleMedium),
          ),
          posts.when(
            loading: () => const LoadingView(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text('No posts yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : Column(
                    children: [
                      for (final p in list)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: PostCard(post: p),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
