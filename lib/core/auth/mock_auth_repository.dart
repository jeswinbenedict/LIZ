import 'dart:async';

import '../../shared/models/profile.dart';
import '../data/mock_data.dart';
import 'auth_repository.dart';

/// In-memory auth for mock mode. Any credentials "work" and drop you into a
/// demo profile so every gated action is testable without a backend.
class MockAuthRepository implements AuthRepository {
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
    return p;
  }

  @override
  Future<Profile> signInWithEmail(String email, String password) =>
      _become(_demoProfile(displayName: email.split('@').first));

  @override
  Future<Profile> signUpWithEmail(
          String email, String password, String displayName) =>
      _become(_demoProfile(displayName: displayName));

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

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<Profile> updateProfile(
      {String? displayName, String? bio, String? avatarUrl}) async {
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
