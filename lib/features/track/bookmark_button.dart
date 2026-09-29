import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../auth/guard.dart';
import '../auth/sign_in_view.dart';
import 'track_controller.dart';

/// Save/bookmark toggle. Saving is also watching: a saved tool's price
/// changes and rises reach Alerts (migration 0044). Works before signing in:
/// a visitor's saves stay in the browser and move into their account when
/// they sign in.
class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({
    super.key,
    required this.toolId,
    this.filledStyle = false,
    this.compact = false,
  });

  final String toolId;

  /// When true renders as a labelled button (tool detail); otherwise an icon.
  final bool filledStyle;

  /// With [filledStyle], an icon-only tonal circle (phone action rows).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(bookmarkControllerProvider).contains(toolId);
    final controller = ref.read(bookmarkControllerProvider.notifier);

    Future<void> toggle() => runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to save tools to your list.',
      action: () async {
        final added = await controller.toggle(toolId);
        if (!context.mounted) return;
        final guest = !ref.read(isSignedInProvider);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: guest && added ? 4 : 1),
              content: Text(
                !added
                    ? 'Removed from saved'
                    : guest
                    ? 'Saved in this browser'
                    : 'Saved',
              ),
              // Offer an account only once there is something to keep.
              action: guest && added
                  ? SnackBarAction(
                      label: 'Keep everywhere',
                      onPressed: () => showSignInSheet(
                        context,
                        prompt:
                            'Sign in to keep your saved tools on every device '
                            'and hear when they change.',
                      ),
                    )
                  : null,
            ),
          );
      },
    );

    if (filledStyle && compact) {
      return IconButton.filled(
        style: LizButtons.tonal(context.liz).merge(
          const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(44, 44))),
        ),
        tooltip: saved ? 'Remove from saved' : 'Save and watch for changes',
        onPressed: toggle,
        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 20),
      );
    }
    if (filledStyle) {
      final style = LizButtons.tonal(context.liz).merge(LizButtons.capsule);
      return FilledButton.icon(
        style: style,
        onPressed: toggle,
        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 18),
        label: Text(saved ? 'Saved' : 'Save'),
      );
    }

    return IconButton(
      onPressed: toggle,
      tooltip: saved ? 'Remove from saved' : 'Save and watch for changes',
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
      color: saved ? context.liz.accent : null,
    );
  }
}
