import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../auth/sign_in_view.dart';
import 'editable_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);

    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 720,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                titleSpacing: 20,
                title: context.isPhone
                    ? const LizWordmark()
                    : Text('Profile',
                        style: Theme.of(context).textTheme.headlineSmall),
                actions: [
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/profile/settings'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (profile == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SignInView(
                      prompt:
                          'Sign in to see your profile, posts, and reviews.'),
                )
              else
                _ProfileBody(profile: profile),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final posts = ref.watch(postFeedProvider(PostFeedKey(userId: profile.id)));
    final reviews = ref.watch(reviewsByUserProvider(profile.id));

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EditableAvatar(profile: profile, radius: 34),
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
              if (profile.role == UserRole.admin) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push('/admin'),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Open admin panel'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('Your reviews',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        reviews.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              Text('Your posts', style: Theme.of(context).textTheme.titleMedium),
        ),
        posts.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
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
        const SizedBox(height: 40),
      ]),
    );
  }
}
