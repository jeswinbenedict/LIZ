import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/grouped_list.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../alerts/alerts_controller.dart';
import '../auth/sign_in_view.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../track/track_controller.dart';
import 'editable_avatar.dart';
import 'profile_parts.dart';

/// Your account (docs/DESIGN.md §8, Profile & Settings): who you are, where
/// your things are, and what you have written.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    final phone = context.isPhone;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          if (phone)
            PhoneTopBar(
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/profile/settings'),
                ),
              ],
            ),
          if (profile == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: const SignInView(
                    prompt: 'Sign in to see your profile, posts, and reviews.',
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(child: _ProfileBody(profile: profile)),
        ],
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = context.isPhone;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));
    final reviews = ref.watch(reviewsByUserProvider(profile.id));
    final savedCount = ref.watch(bookmarkControllerProvider).length;
    final unread = ref.watch(unreadAlertsProvider);

    final header = ProfileHeader(
      profile: profile,
      avatar: EditableAvatar(profile: profile, radius: phone ? 32 : 40),
      figures: [
        (savedCount, 'saved'),
        (reviews.value?.length, 'reviews'),
        (posts.value?.length, 'posts'),
      ],
    );

    final places = LizGroup(
      title: 'Your account',
      children: [
        LizGroupRow(
          icon: Icons.bookmark_outline,
          title: 'Saved',
          value: savedCount == 0 ? null : '$savedCount',
          onTap: () => context.go('/saved'),
        ),
        LizGroupRow(
          icon: Icons.notifications_none,
          title: 'Alerts',
          value: unread == 0 ? null : '$unread new',
          onTap: () => context.push('/alerts'),
        ),
        LizGroupRow(
          icon: Icons.settings_outlined,
          title: 'Settings',
          onTap: () => context.push('/profile/settings'),
        ),
        if (profile.role == UserRole.admin)
          LizGroupRow(
            icon: Icons.shield_outlined,
            title: 'Admin console',
            subtitle: 'Catalog, news, moderation and health',
            onTap: () => context.push('/admin'),
          ),
      ],
    );

    final activity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileHeading('Your reviews'),
        reviews.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? ProfileEmptyPanel(
                  icon: Icons.rate_review_outlined,
                  text: 'No reviews yet. Rate a tool from its page.',
                  action: 'Find a tool',
                  onAction: () => context.go('/'),
                )
              : ProfilePanel(
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
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
        ProfileHeading('Your posts'),
        posts.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? const ProfileEmptyPanel(
                  icon: Icons.forum_outlined,
                  text: 'No posts yet.',
                )
              : Column(
                  children: [
                    for (final post in list) ...[
                      PostCard(post: post),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );

    // Wide: what you wrote on the left, your account on the right, both under
    // the header. Narrow: one column, the account first.
    final wide = width >= 1100;
    return MaxWidth(
      maxWidth: 1080 + gutter * 2,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, phone ? 12 : 36, gutter, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            SizedBox(height: phone ? 24 : 36),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: activity),
                  const SizedBox(width: 32),
                  Expanded(flex: 3, child: places),
                ],
              )
            else ...[
              places,
              const SizedBox(height: 32),
              activity,
            ],
          ],
        ),
      ),
    );
  }
}
