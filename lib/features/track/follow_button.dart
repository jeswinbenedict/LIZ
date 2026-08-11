import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/guard.dart';
import 'track_controller.dart';

/// Follow a tool to get updates (launch, price changes). Prompts sign-in.
class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.toolId});
  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followControllerProvider).contains(toolId);
    final controller = ref.read(followControllerProvider.notifier);

    Future<void> toggle() => runGuardedAction(
          context,
          prompt: 'Sign in to follow tools and get updates.',
          action: () async {
            final added = await controller.toggle(toolId);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                  content: Text(added
                      ? 'Following — we\'ll notify you of updates'
                      : 'Unfollowed'),
                ));
            }
          },
        );

    return following
        ? OutlinedButton.icon(
            onPressed: toggle,
            icon: const Icon(Icons.notifications_active, size: 18),
            label: const Text('Following'),
          )
        : OutlinedButton.icon(
            onPressed: toggle,
            icon: const Icon(Icons.notifications_none, size: 18),
            label: const Text('Follow'),
          );
  }
}
