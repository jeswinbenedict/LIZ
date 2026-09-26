import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_expiry.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import 'sign_in_view.dart';

/// Runs an identity action. If the repository reports the user is a guest
/// ([AuthRequiredException]), presents the sign-in sheet and — on success —
/// retries the action once, so the user lands exactly where they were.
Future<void> runGuardedAction(
  BuildContext context, {
  required Future<void> Function() action,
  String? prompt,
  VoidCallback? onDone,
  WidgetRef? ref,
}) async {
  Future<void> attempt() async {
    await action();
    onDone?.call();
  }

  Future<void> offerSignIn(String? reason) async {
    if (!context.mounted) return;
    final signedIn = await showSignInSheet(context, prompt: reason ?? prompt);
    if (signedIn && context.mounted) {
      try {
        await attempt();
      } catch (e) {
        _toast(context, e);
      }
    }
  }

  try {
    await attempt();
  } on AuthRequiredException {
    await offerSignIn(null);
  } catch (e) {
    // A session that expired or was revoked while the tab sat open is not
    // "something went wrong" — it is the same situation a guest is in, and it
    // has the same fix. Tokens last an hour, so this is an ordinary Tuesday.
    if (isSessionExpired(e)) {
      // Clear the dead session first, or the sheet opens believing someone is
      // still signed in and the retry fails the same way.
      await ref?.read(authRepositoryProvider).signOut();
      await offerSignIn('Your session expired. Sign in again to continue.');
      return;
    }
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
