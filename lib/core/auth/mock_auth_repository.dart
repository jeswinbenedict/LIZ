import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/profile.dart';
import '../data/mock_data.dart';
import '../errors.dart';
import 'auth_repository.dart';

/// In-memory auth for mock mode. Any credentials "work" and drop you into a
/// demo profile so every gated action is testable without a backend.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository() {
    _restore();
  }

  // The demo session survives a reload, like a real one, so the sign-in
  // wall behaves the same in demo mode and the browser checks can reload.
  static const _sessionKey = 'liz.demo_session';
  final _restored = Completer<void>();

  @override
  Future<void> get restored => _restored.future;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_sessionKey);
      if (name != null && _current == null) {
        _current = _demoProfile(displayName: name);
        _controller.add(_current);
      }
    } catch (_) {
      // No storage (a widget test without mock values): start signed out.
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  Future<void> _remember(String? name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name == null) {
        await prefs.remove(_sessionKey);
      } else {
        await prefs.setString(_sessionKey, name);
      }
    } catch (_) {}
  }

  // Demo mode has no second factor to check; the console is open.
  @override
  Future<TwoStep> twoStep() async => const TwoStep(TwoStepStatus.verified);

  @override
  Future<TotpSetup> startTwoStepSetup() async => const TotpSetup(
    factorId: 'demo',
    uri: 'otpauth://totp/Liz:demo?secret=DEMO&issuer=Liz',
    secret: 'DEMO',
  );

  @override
  Future<void> verifyTwoStep(String factorId, String code) async {}

  @override
  Future<Profile> completeTwoStepSignIn(String code) => signInAsDemo();

  final _controller = StreamController<Profile?>.broadcast();
  Profile? _current;

  @override
  Profile? get currentProfile => _current;

  @override
  String? get currentUserId => _current?.id;

  @override
  Stream<Profile?> authStateChanges() => _controller.stream;

  Profile _demoProfile({String? displayName}) => Profile(
    id: 'u-me',
    username: 'you',
    displayName: displayName ?? 'You',
    bio: 'Exploring the frontier on Liz.',
    role: UserRole.admin, // demo user can see the admin panel
    createdAt: DateTime.now(),
  );

  Future<Profile> _become(Profile p) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _current = p;
    _controller.add(p);
    unawaited(_remember(p.displayName));
    return p;
  }

  @override
  Future<Profile> signInWithEmail(String email, String password) =>
      _become(_demoProfile(displayName: email.split('@').first));

  @override
  Future<Profile> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) => _become(_demoProfile(displayName: displayName));

  @override
  Future<void> sendMagicLink(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<Profile> signInWithGoogle() => _become(_demoProfile());

  @override
  Future<Profile> signInWithApple() => _become(_demoProfile());

  @override
  Future<Profile> signInAsDemo() => _become(_demoProfile());

  /// Recorded so a test can assert a link was requested without a backend.
  String? lastPasswordResetEmail;

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    lastPasswordResetEmail = email;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (newPassword.length < 8) {
      throw const LizException('Password must be at least 8 characters.');
    }
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
    await _remember(null);
  }

  @override
  Future<Profile> updateProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final c = _current;
    if (c == null) throw StateError('Not signed in');
    _current = Profile(
      id: c.id,
      username: c.username,
      displayName: displayName ?? c.displayName,
      avatarUrl: avatarUrl ?? c.avatarUrl,
      bio: bio ?? c.bio,
      role: c.role,
      createdAt: c.createdAt,
    );
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> registerDevice(String token, String platform) async {}

  @override
  Future<void> deleteAccount() async {
    await signOut();
  }

  // Expose mock profiles so seeded content can reference known authors.
  List<Profile> get knownProfiles => MockData.profiles;
}
