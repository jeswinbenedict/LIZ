/// What to tell a person when Firebase refuses a sign-in action, by the
/// error code Firebase reports.
///
/// Firebase's own messages are written for developers ("The supplied auth
/// credential is incorrect, malformed or has expired."), and a few would say
/// whether an address has an account — which a sign-in form must not.
String authErrorMessage(String code) {
  switch (code) {
    // One message for all three: which one it was is exactly what someone
    // probing for accounts wants to know.
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-login-credentials':
      return 'That email and password don\'t match an account.';
    case 'email-already-in-use':
      return 'That email already has an account. Sign in instead, or reset '
          'the password.';
    case 'invalid-email':
      return 'That doesn\'t look like an email address.';
    case 'weak-password':
      return 'Choose a longer password — at least 6 characters.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes and try again.';
    case 'user-disabled':
      return 'This account has been suspended.';
    case 'network-request-failed':
      return 'No connection. Check your internet and try again.';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
    case 'user-cancelled':
      return 'Sign-in was cancelled.';
    case 'popup-blocked':
      return 'Your browser blocked the sign-in window. Allow pop-ups for '
          'this site and try again.';
    case 'account-exists-with-different-credential':
      return 'That email already signs in another way. Use that, then you '
          'can carry on.';
    case 'operation-not-allowed':
    // Firebase Authentication not yet switched on for the project.
    case 'configuration-not-found':
      return 'That way of signing in isn\'t available yet.';
    case 'requires-recent-login':
      return 'For your security, sign out and sign in again, then retry.';
    case 'unverified-email':
      return 'Confirm your email address first — we\'ve sent you a link.';
    case 'invalid-verification-code':
    case 'invalid-totp-code':
      return 'That code didn\'t work. Codes change every 30 seconds — try '
          'the current one.';
    case 'expired-action-code':
    case 'invalid-action-code':
      return 'This link has expired or was already used. Ask for a new one.';
    case 'unauthorized-domain':
      return 'Sign-in isn\'t set up for this address yet.';
    default:
      return 'Something went wrong signing in. Try again.';
  }
}
