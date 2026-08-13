import '../../shared/models/profile.dart';

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
      String email, String password, String displayName);
  Future<void> sendMagicLink(String email);
  Future<Profile> signInWithGoogle();
  Future<Profile> signInWithApple();

  /// Demo-only shortcut used in mock mode so the UI is fully testable without
  /// real providers. No-op on the live backend.
  Future<Profile> signInAsDemo();

  Future<void> signOut();

  Future<Profile> updateProfile({String? displayName, String? bio, String? avatarUrl});

  /// Store an FCM token for push (idempotent).
  Future<void> registerDevice(String token, String platform);

  /// Request account deletion (App Store requirement).
  Future<void> deleteAccount();
}
