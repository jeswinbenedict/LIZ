import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Recognises "your session is no longer valid" among everything else that can
/// go wrong.
///
/// The sign-in guard already recovers gracefully when a *guest* attempts an
/// action: it offers the sheet and retries. A session that expired or was
/// revoked while the tab sat open looked nothing like that — it surfaced as a
/// PostgREST or auth error and the reader got "Something went wrong", with no
/// hint that signing in again was the fix.
///
/// Tokens last an hour and Liz is the kind of thing left open in a tab, so
/// this is an ordinary Tuesday rather than an edge case.
bool isSessionExpired(Object error) {
  // Firebase, which signs people in now (migration 0055): a token it can no
  // longer refresh, or an account removed or disabled since.
  if (error is FirebaseAuthException) {
    return const {
      'user-token-expired',
      'user-not-found',
      'user-disabled',
      'invalid-user-token',
    }.contains(error.code);
  }

  if (error is AuthException) {
    // Supabase reports these both ways depending on which endpoint answered.
    if (error.statusCode == '401' || error.statusCode == '403') return true;
    return _looksExpired(error.message);
  }

  if (error is PostgrestException) {
    // PGRST301 is PostgREST's own code for a JWT that no longer verifies.
    // 42501 is deliberately excluded: that is row-level security refusing a
    // perfectly valid session, and treating it as expiry would send someone
    // to sign in again for something signing in cannot fix.
    if (error.code == 'PGRST301') return true;
    return _looksExpired(error.message);
  }

  if (error is FunctionException) {
    return error.status == 401;
  }

  return false;
}

bool _looksExpired(String? message) {
  if (message == null) return false;
  final text = message.toLowerCase();
  return text.contains('jwt expired') ||
      text.contains('token is expired') ||
      text.contains('invalid claim') ||
      text.contains('session from session_id claim in jwt does not exist') ||
      text.contains('refresh token not found');
}
