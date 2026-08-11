import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/guard.dart';
import 'track_controller.dart';

/// Save/bookmark toggle. Optimistic, and prompts sign-in for guests.
class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({
    super.key,
    required this.toolId,
    this.filledStyle = false,
  });

  final String toolId;

  /// When true renders as a labelled button (tool detail); otherwise an icon.
  final bool filledStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(bookmarkControllerProvider).contains(toolId);
    final controller = ref.read(bookmarkControllerProvider.notifier);

    Future<void> toggle() => runGuardedAction(
          context,
          prompt: 'Sign in to save tools to your list.',
          action: () async {
            final added = await controller.toggle(toolId);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                  content: Text(added ? 'Saved' : 'Removed from saved'),
                ));
            }
          },
        );

    if (filledStyle) {
      return saved
          ? OutlinedButton.icon(
              onPressed: toggle,
              icon: const Icon(Icons.bookmark),
              label: const Text('Saved'),
            )
          : FilledButton.tonalIcon(
              onPressed: toggle,
              icon: const Icon(Icons.bookmark_border),
              label: const Text('Save'),
            );
    }

    return IconButton(
      onPressed: toggle,
      tooltip: saved ? 'Remove from saved' : 'Save',
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
      color: saved ? Theme.of(context).colorScheme.primary : null,
    );
  }
}
