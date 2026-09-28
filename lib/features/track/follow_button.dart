import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/guard.dart';
import 'track_controller.dart';

/// Follow a tool to hear when it changes. Prompts sign-in.
///
/// The alert is deliberately narrow — a move between two known prices, or a
/// climb into the top ten — so following something does not become a feed of
/// noise. See migration 0021.
class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.toolId, this.compact = false});
  final String toolId;

  /// An icon-only tonal circle (phone action rows).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followControllerProvider).contains(toolId);
    final controller = ref.read(followControllerProvider.notifier);

    Future<void> toggle() => runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to follow tools and get updates.',
      action: () async {
        final added = await controller.toggle(toolId);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
                content: Text(
                  added
                      ? 'Following — we\'ll tell you if its pricing changes '
                            'or it starts climbing'
                      : 'Unfollowed',
                ),
              ),
            );
        }
      },
    );

    if (compact) {
      return IconButton.filled(
        style: LizButtons.tonal(context.liz).merge(
          const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(44, 44))),
        ),
        tooltip: following ? 'Following — tap to unfollow' : 'Follow',
        onPressed: toggle,
        icon: Icon(
          following ? Icons.notifications_active : Icons.notifications_none,
          size: 20,
        ),
      );
    }
    return FilledButton.icon(
      style: LizButtons.tonal(context.liz).merge(LizButtons.capsule),
      onPressed: toggle,
      icon: Icon(
        following ? Icons.notifications_active : Icons.notifications_none,
        size: 18,
      ),
      label: Text(following ? 'Following' : 'Follow'),
    );
  }
}
