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
import '../../shared/widgets/time_ago.dart';
import '../alerts/alerts_controller.dart';
import '../auth/sign_in_view.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../track/track_controller.dart';
import 'editable_avatar.dart';

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
    final p = context.liz;
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));
    final reviews = ref.watch(reviewsByUserProvider(profile.id));
    final savedCount = ref.watch(bookmarkControllerProvider).length;
    final unread = ref.watch(unreadAlertsProvider);

    return MaxWidth(
      maxWidth: 680 + gutter * 2,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, phone ? 12 : 40, gutter, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Who you are.
            Column(
              children: [
                EditableAvatar(profile: profile, radius: 44),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          profile.displayName,
                          textAlign: TextAlign.center,
                          style: LizText.title1.copyWith(color: p.textPrimary),
                        ),
                      ),
                    ),
                    if (profile.role.canModerate) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified,
                        size: 20,
                        color: p.accent,
                        semanticLabel: 'Moderator',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${profile.username}  ·  Joined ${timeAgo(profile.createdAt)} ago',
                  textAlign: TextAlign.center,
                  style: LizText.subhead.copyWith(color: p.textSecondary),
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      profile.bio!,
                      textAlign: TextAlign.center,
                      style: LizText.body.copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),

            // Where your things are.
            LizGroup(
              children: [
                LizGroupRow(
                  icon: Icons.bookmark,
                  title: 'Saved',
                  value: savedCount == 0 ? null : '$savedCount',
                  onTap: () => context.go('/saved'),
                ),
                LizGroupRow(
                  icon: Icons.notifications,
                  iconColor: p.caution,
                  title: 'Alerts',
                  value: unread == 0 ? null : '$unread new',
                  onTap: () => context.push('/alerts'),
                ),
                LizGroupRow(
                  icon: Icons.settings,
                  iconColor: p.textSecondary,
                  title: 'Settings',
                  onTap: () => context.push('/profile/settings'),
                ),
                if (profile.role == UserRole.admin)
                  LizGroupRow(
                    icon: Icons.shield_outlined,
                    iconColor: p.positive,
                    title: 'Admin console',
                    subtitle: 'Catalog, news, moderation and health',
                    onTap: () => context.push('/admin'),
                  ),
              ],
            ),

            // What you have written.
            const SizedBox(height: 32),
            _Heading('Your reviews'),
            reviews.when(
              loading: () => const LoadingView(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? _Quiet('No reviews yet. Rate a tool from its page.')
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ReviewTile(review: list[i]),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 28),
            _Heading('Your posts'),
            posts.when(
              loading: () => const LoadingView(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? _Quiet('No posts yet.')
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
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: LizText.title3.copyWith(color: context.liz.textPrimary),
      ),
    ),
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: LizText.callout.copyWith(color: context.liz.textSecondary),
    ),
  );
}
