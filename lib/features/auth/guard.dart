import 'package:flutter/material.dart';

import '../../core/errors.dart';
import 'sign_in_view.dart';

/// Runs an identity action. If the repository reports the user is a guest
/// ([AuthRequiredException]), presents the sign-in sheet and — on success —
/// retries the action once, so the user lands exactly where they were.
Future<void> runGuardedAction(
  BuildContext context, {
  required Future<void> Function() action,
  String? prompt,
  VoidCallback? onDone,
}) async {
  Future<void> attempt() async {
    await action();
    onDone?.call();
  }

  try {
    await attempt();
  } on AuthRequiredException {
    if (!context.mounted) return;
    final signedIn = await showSignInSheet(context, prompt: prompt);
    if (signedIn && context.mounted) {
      try {
        await attempt();
      } catch (e) {
        _toast(context, e);
      }
    }
  } catch (e) {
    _toast(context, e);
  }
}

void _toast(BuildContext context, Object error) {
  if (!context.mounted) return;
  final msg = error is LizException ? error.message : 'Something went wrong.';
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
