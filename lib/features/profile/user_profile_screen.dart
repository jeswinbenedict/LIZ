import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/top_bar.dart';
import '../../shared/widgets/user_avatar.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../track/follow_user_button.dart';
import 'profile_parts.dart';

/// Anyone's public profile: who they are, Follow, and what they wrote — the
/// same page as your own (ProfileScreen), without the account settings.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileByIdProvider(userId));

    return Scaffold(
      appBar: LizTopBar(
        title: profileAsync.maybeWhen(
          data: (profile) => profile?.displayName ?? 'Profile',
          orElse: () => null,
        ),
        section: ('Community', '/community'),
        fallback: '/community',
        // The person's name is the page's heading, beside their avatar.
        titleIsHeading: false,
      ),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) => ErrorView(
          onRetry: () => ref.invalidate(profileByIdProvider(userId)),
        ),
        data: (profile) => profile == null
            ? const EmptyView(
                icon: Icons.person_off_outlined,
                title: 'User not found',
                message: 'This profile may have been removed.',
                headingLevel: 1,
              )
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
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final me = ref.watch(currentUserProvider);
    final isSelf = me?.id == profile.id;
    final reviews = ref.watch(reviewsByUserProvider(profile.id));
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));
    final first = profile.displayName.split(' ').first;

    return MaxWidth(
      maxWidth: 760 + gutter * 2,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, phone ? 12 : 36, gutter, 48),
        children: [
          ProfileHeader(
            profile: profile,
            avatar: UserAvatar(profile: profile, radius: phone ? 32 : 40),
            figures: [
              (reviews.value?.length, 'reviews'),
              (posts.value?.length, 'posts'),
            ],
            // Your own page, reached from a post: the way to edit it, rather
            // than a Follow button aimed at yourself.
            trailing: isSelf
                ? OutlinedButton(
                    onPressed: () => context.go('/profile'),
                    child: const Text('Edit profile'),
                  )
                : FollowUserButton(userId: profile.id),
          ),
          SizedBox(height: phone ? 28 : 40),
          const ProfileHeading('Reviews'),
          reviews.when(
            loading: () => const LoadingView(),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? ProfileEmptyPanel(
                    icon: Icons.rate_review_outlined,
                    text: '$first has not reviewed a tool yet.',
                  )
                : ProfilePanel(
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: context.liz.hairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ReviewTile(review: list[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 32),
          const ProfileHeading('Posts'),
          posts.when(
            loading: () => const LoadingView(),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? ProfileEmptyPanel(
                    icon: Icons.forum_outlined,
                    text: '$first has not posted yet.',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        PostCard(post: list[i]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
