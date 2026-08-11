import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models/profile.dart';

/// Drives the sign-in / sign-up flows and exposes a busy flag for buttons.
class AuthController extends StateNotifier<bool> {
  AuthController(this._ref) : super(false);
  final Ref _ref;

  Future<T> _run<T>(Future<T> Function() action) async {
    state = true;
    try {
      return await action();
    } finally {
      if (mounted) state = false;
    }
  }

  Future<Profile> signInWithEmail(String email, String password) =>
      _run(() => _ref.read(authRepositoryProvider).signInWithEmail(email, password));

  Future<Profile> signUp(String email, String password, String name) => _run(
      () => _ref.read(authRepositoryProvider).signUpWithEmail(email, password, name));

  Future<void> sendMagicLink(String email) =>
      _run(() => _ref.read(authRepositoryProvider).sendMagicLink(email));

  Future<Profile> signInWithGoogle() =>
      _run(() => _ref.read(authRepositoryProvider).signInWithGoogle());

  Future<Profile> signInWithApple() =>
      _run(() => _ref.read(authRepositoryProvider).signInWithApple());

  Future<Profile> signInAsDemo() =>
      _run(() => _ref.read(authRepositoryProvider).signInAsDemo());

  Future<void> signOut() =>
      _run(() => _ref.read(authRepositoryProvider).signOut());
}

final authControllerProvider =
    StateNotifierProvider<AuthController, bool>((ref) => AuthController(ref));

/// True when Apple Sign In should be offered (iOS/macOS require it if any
/// social login is present).
bool get shouldOfferApple =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    kIsWeb;
