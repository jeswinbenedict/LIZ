import '../../shared/models/profile.dart';

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

/// Authentication surface. Guest browsing is always allowed; only identity
/// actions require a signed-in session.
abstract interface class AuthRepository {
  /// Current profile, or null when browsing as a guest.
  Profile? get currentProfile;

  String? get currentUserId => currentProfile?.id;

  /// Emits whenever the session changes (sign in / out / refresh).
  Stream<Profile?> authStateChanges();

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
}
