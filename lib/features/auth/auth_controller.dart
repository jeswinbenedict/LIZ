import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/profile.dart';

/// Drives the sign-in / sign-up flows and exposes a busy flag for buttons.
class AuthController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<T> _run<T>(Future<T> Function() action) async {
    state = true;
    try {
      return await action();
    } finally {
      if (ref.mounted) state = false;
    }
  }

  Future<Profile> signInWithEmail(String email, String password) async {
    final profile = await _run(
      () => ref.read(authRepositoryProvider).signInWithEmail(email, password),
    );
    Analytics.track('sign_in');
    return profile;
  }

  Future<Profile> signUp(String email, String password, String name) async {
    final profile = await _run(
      () => ref
          .read(authRepositoryProvider)
          .signUpWithEmail(email, password, name),
    );
    Analytics.track('sign_up');
    return profile;
  }

  Future<void> sendMagicLink(String email) =>
      _run(() => ref.read(authRepositoryProvider).sendMagicLink(email));

  Future<Profile> signInWithGoogle() =>
      _run(() => ref.read(authRepositoryProvider).signInWithGoogle());

  Future<Profile> signInWithApple() =>
      _run(() => ref.read(authRepositoryProvider).signInWithApple());

  /// Finishes a sign-in that asked for an authenticator code.
  Future<Profile> completeTwoStepSignIn(String code) =>
      _run(() => ref.read(authRepositoryProvider).completeTwoStepSignIn(code));

  Future<Profile> signInAsDemo() =>
      _run(() => ref.read(authRepositoryProvider).signInAsDemo());

  Future<void> signOut() =>
      _run(() => ref.read(authRepositoryProvider).signOut());
}

final authControllerProvider = NotifierProvider<AuthController, bool>(
  AuthController.new,
);

/// True when Apple Sign In should be offered (iOS/macOS require it if any
/// social login is present).
bool get shouldOfferApple =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    kIsWeb;
