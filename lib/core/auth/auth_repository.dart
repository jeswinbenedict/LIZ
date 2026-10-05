import '../../shared/models/profile.dart';
import '../errors.dart';

/// Where the signed-in moderator stands with two-step verification
/// (migration 0042).
enum TwoStepStatus {
  /// This session has passed a code check. The console is open.
  verified,

  /// An authenticator is set up; this session still needs a code from it.
  needsCode,

  /// No authenticator yet.
  needsSetup,
}

class TwoStep {
  const TwoStep(this.status, {this.factorId});
  final TwoStepStatus status;

  /// The authenticator to check a code against, when there is one.
  final String? factorId;
}

/// A new authenticator, waiting for its first code.
class TotpSetup {
  const TotpSetup({
    required this.factorId,
    required this.uri,
    required this.secret,
  });
  final String factorId;

  /// otpauth:// address, drawn as the QR code an authenticator app scans.
  final String uri;

  /// The same key, for typing in by hand.
  final String secret;
}

/// Thrown by a sign-in when the account has two-step verification: the
/// password was right, and [AuthRepository.completeTwoStepSignIn] with a code
/// from the authenticator app finishes the sign-in.
class TwoStepRequiredException extends LizException {
  const TwoStepRequiredException()
    : super('Enter the code from your authenticator app.');
}

/// Firebase adds a second factor only to a session signed in a few minutes
/// ago; an older one is refused (CREDENTIAL_TOO_OLD_LOGIN_AGAIN). Signing in
/// again is the way through, so the two-step page offers it.
class RecentSignInRequiredException extends LizException {
  const RecentSignInRequiredException()
    : super(
        'For your security, sign in again before setting up two-step '
        'verification.',
      );
}

/// Authentication surface. Guest browsing is always allowed; only identity
/// actions require a signed-in session.
abstract interface class AuthRepository {
  /// Current profile, or null when browsing as a guest.
  Profile? get currentProfile;

  String? get currentUserId => currentProfile?.id;

  /// Emits whenever the session changes (sign in / out / refresh).
  Stream<Profile?> authStateChanges();

  /// Completes once the session a returning visitor left behind has been
  /// restored or found missing. Until then a null [currentProfile] does not
  /// mean signed out — the sign-in wall waits for this rather than bounce a
  /// signed-in person to the sign-in page while Firebase loads.
  Future<void> get restored;

  Future<Profile> signInWithEmail(String email, String password);
  Future<Profile> signUpWithEmail(
    String email,
    String password,
    String displayName,
  );
  Future<void> sendMagicLink(String email);
  Future<Profile> signInWithGoogle();
  Future<Profile> signInWithApple();

  /// Demo-only shortcut used in mock mode so the UI is fully testable without
  /// real providers. No-op on the live backend.
  Future<Profile> signInAsDemo();

  /// Send a password-reset link to [email].
  ///
  /// Always completes without error, even for an address with no account.
  /// Saying "no such user" here turns the form into a way to discover who has
  /// one — and a reset form is exactly where someone would go looking.
  Future<void> sendPasswordReset(String email);

  /// Set a new password for the session opened by a reset link.
  Future<void> updatePassword(String newPassword);

  Future<void> signOut();

  Future<Profile> updateProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
  });

  /// Store an FCM token for push (idempotent).
  Future<void> registerDevice(String token, String platform);

  /// Request account deletion (App Store requirement).
  Future<void> deleteAccount();

  /// Two-step verification, which moderator powers require once any
  /// moderator has turned it on (migration 0042).
  Future<TwoStep> twoStep();

  /// Creates an authenticator for this account and returns what the
  /// authenticator app needs. Replaces one left half set up.
  Future<TotpSetup> startTwoStepSetup();

  /// Checks a six-digit code. On success the session is upgraded, and the
  /// requirement is switched on for every moderator from then on.
  Future<void> verifyTwoStep(String factorId, String code);

  /// Finishes a sign-in that threw [TwoStepRequiredException].
  Future<Profile> completeTwoStepSignIn(String code);
}
