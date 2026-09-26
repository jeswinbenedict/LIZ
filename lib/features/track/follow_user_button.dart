import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/guard.dart';
import 'track_controller.dart';

/// Follow / Following toggle for another user. Prompts sign-in for guests.
class FollowUserButton extends ConsumerWidget {
  const FollowUserButton({
    super.key,
    required this.userId,
    this.compact = false,
  });
  final String userId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followUserControllerProvider).contains(userId);
    final controller = ref.read(followUserControllerProvider.notifier);

    Future<void> toggle() => runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to follow people.',
      action: () async {
        final added = await controller.toggle(userId);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
                content: Text(added ? 'Following' : 'Unfollowed'),
              ),
            );
        }
      },
    );

    if (following) {
      return OutlinedButton.icon(
        onPressed: toggle,
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Following'),
      );
    }
    return FilledButton.icon(
      onPressed: toggle,
      icon: const Icon(Icons.person_add_alt_1, size: 18),
      label: const Text('Follow'),
    );
  }
}
