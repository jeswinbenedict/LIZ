import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/grouped_list.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
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
    final phone = context.isPhone;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));
    final reviews = ref.watch(reviewsByUserProvider(profile.id));
    final savedCount = ref.watch(bookmarkControllerProvider).length;
    final unread = ref.watch(unreadAlertsProvider);

    final header = _Header(
      profile: profile,
      saved: savedCount,
      reviews: reviews.value?.length,
      posts: posts.value?.length,
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
        _Heading('Your reviews'),
        reviews.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? _EmptyPanel(
                  icon: Icons.rate_review_outlined,
                  text: 'No reviews yet. Rate a tool from its page.',
                  action: 'Find a tool',
                  onAction: () => context.go('/'),
                )
              : _Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ReviewTile(review: list[i]),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 32),
        _Heading('Your posts'),
        posts.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? const _EmptyPanel(
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

/// The avatar, the name as the page's heading, a quiet role badge, when they
/// joined, the bio, and three figures — set as type, not tiles.
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.saved,
    required this.reviews,
    required this.posts,
  });
  final Profile profile;
  final int saved;
  final int? reviews;
  final int? posts;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = context.isPhone;
    final joined = DateFormat.yMMMM().format(profile.createdAt.toLocal());
    final role = switch (profile.role) {
      UserRole.admin => 'Admin',
      UserRole.moderator => 'Moderator',
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditableAvatar(profile: profile, radius: phone ? 32 : 40),
        SizedBox(width: phone ? 16 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    container: true,
                    header: true,
                    headingLevel: 1,
                    child: Text(
                      profile.displayName,
                      style: (phone ? LizText.title1 : LizText.largeTitle)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                  if (role != null) LizPill(label: role),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.username}  ·  Joined $joined',
                style: LizText.subhead.copyWith(color: p.textSecondary),
              ),
              if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    profile.bio!,
                    style: LizText.body.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _Figure(value: saved, label: 'saved'),
                  _Figure(value: reviews, label: 'reviews'),
                  _Figure(value: posts, label: 'posts'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "12 saved": the figure in ink, the noun in grey. A dash while unknown.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value == null ? '—' : '$value',
            style: LizText.headline.copyWith(
              color: p.textPrimary,
              fontFeatures: LizText.tabular,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      container: true,
      header: true,
      child: Text(
        text,
        style: LizText.title3.copyWith(color: context.liz.textPrimary),
      ),
    ),
  );
}

/// A section's frame, kept when it has rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: child,
    );
  }
}

/// An empty section keeps its frame: an icon, one sentence, and at most one
/// way forward.
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        // The button sits beside the sentence where there is room for both,
        // and under it on a narrow screen or with large text.
        child: LayoutBuilder(
          builder: (context, box) {
            final button = action != null && onAction != null
                ? OutlinedButton(onPressed: onAction, child: Text(action!))
                : null;
            final sentence = Text(
              text,
              style: LizText.callout.copyWith(color: p.textSecondary),
            );
            final beside = box.maxWidth >= 440;
            return Row(
              crossAxisAlignment: beside
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: p.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: beside || button == null
                      ? sentence
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sentence,
                            const SizedBox(height: 12),
                            button,
                          ],
                        ),
                ),
                if (beside && button != null) ...[
                  const SizedBox(width: 12),
                  button,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
