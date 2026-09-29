import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/profile.dart';
import '../config/env.dart';
import '../errors.dart';
import 'auth_repository.dart';

/// Live auth backed by Supabase Auth + the `profiles` table.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client) {
    _sub = _client.auth.onAuthStateChange.listen((event) async {
      final user = event.session?.user;
      if (user == null) {
        _current = null;
        _out.add(null);
      } else {
        _current = await _loadProfile(user.id) ?? _fallbackProfile(user);
        _out.add(_current);
      }
    });
  }

  final SupabaseClient _client;
  late final StreamSubscription _sub;
  final _out = StreamController<Profile?>.broadcast();
  Profile? _current;

  @override
  Profile? get currentProfile => _current;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<Profile?> authStateChanges() => _out.stream;

  @override
  Future<TwoStep> twoStep() async {
    final mfa = _client.auth.mfa;
    if (mfa.getAuthenticatorAssuranceLevel().currentLevel ==
        AuthenticatorAssuranceLevels.aal2) {
      return const TwoStep(TwoStepStatus.verified);
    }
    final factors = await mfa.listFactors();
    if (factors.totp.isNotEmpty) {
      return TwoStep(TwoStepStatus.needsCode, factorId: factors.totp.first.id);
    }
    return const TwoStep(TwoStepStatus.needsSetup);
  }

  @override
  Future<TotpSetup> startTwoStepSetup() async {
    final mfa = _client.auth.mfa;
    // A setup abandoned before its first code leaves an unverified factor
    // behind, and a second one cannot be created beside it.
    final factors = await mfa.listFactors();
    for (final f in factors.all) {
      if (f.status == FactorStatus.unverified) {
        await mfa.unenroll(f.id);
      }
    }
    final res = await mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Liz',
      friendlyName: 'Liz authenticator',
    );
    final totp = res.totp;
    if (totp == null) {
      throw const LizException('Could not start two-step verification.');
    }
    return TotpSetup(factorId: res.id, uri: totp.uri, secret: totp.secret);
  }

  @override
  Future<void> verifyTwoStep(String factorId, String code) async {
    try {
      await _client.auth.mfa.challengeAndVerify(
        factorId: factorId,
        code: code.trim(),
      );
    } on AuthException {
      throw const LizException(
        "That code didn't work. Codes change every 30 seconds — try the "
        'current one.',
      );
    }
    // Idempotent, and only effective for an aal2 moderator.
    try {
      await _client.rpc<dynamic>('require_moderator_mfa');
    } catch (_) {}
  }

  Profile _fallbackProfile(User user) => Profile(
    id: user.id,
    username: user.email?.split('@').first ?? 'user',
    displayName:
        (user.userMetadata?['display_name'] as String?) ??
        user.email?.split('@').first ??
        'User',
    avatarUrl: user.userMetadata?['avatar_url'] as String?,
    role: UserRole.user,
    createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
  );

  Future<Profile?> _loadProfile(String id) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<Profile> _afterAuth(AuthResponse res) async {
    final user = res.user;
    if (user == null) throw const LizException('Sign-in failed.');
    _current = await _loadProfile(user.id) ?? _fallbackProfile(user);
    _out.add(_current);
    return _current!;
  }

  @override
  Future<Profile> signInWithEmail(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return await _afterAuth(res);
    } on AuthException catch (e) {
      throw LizException(e.message);
    }
  }

  @override
  Future<Profile> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      return await _afterAuth(res);
    } on AuthException catch (e) {
      throw LizException(e.message);
    }
  }

  @override
  Future<void> sendMagicLink(String email) =>
      _client.auth.signInWithOtp(email: email);

  @override
  Future<Profile> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
    // Completion arrives via the auth state stream after the redirect.
    throw const LizException('Complete Google sign-in in the opened window.');
  }

  @override
  Future<Profile> signInWithApple() async {
    await _client.auth.signInWithOAuth(OAuthProvider.apple);
    throw const LizException('Complete Apple sign-in in the opened window.');
  }

  @override
  Future<Profile> signInAsDemo() =>
      throw const LizException('Demo sign-in is only available in mock mode.');

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        // Where the link lands. Supabase appends the recovery token, and the
        // app reads it from the session the SDK opens on arrival.
        redirectTo: Env.passwordResetRedirect,
      );
    } on AuthException catch (e) {
      // Rate limiting is the one refusal worth passing on: it is actionable,
      // and it is not a statement about whether the address exists.
      if (e.statusCode == '429') throw LizException(e.message);
      // Anything else is swallowed on purpose. See the interface note.
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw LizException(e.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<Profile> updateProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final id = currentUserId;
    if (id == null) throw const AuthRequiredException();
    final row = await _client
        .from('profiles')
        .update({
          'display_name': ?displayName,
          'bio': ?bio,
          'avatar_url': ?avatarUrl,
        })
        .eq('id', id)
        .select()
        .single();
    _current = Profile.fromJson(row);
    _out.add(_current);
    return _current!;
  }

  @override
  Future<void> registerDevice(String token, String platform) async {
    final id = currentUserId;
    if (id == null) return;
    await _client.from('devices').upsert({
      'user_id': id,
      'fcm_token': token,
      'platform': platform,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'fcm_token');
  }

  @override
  Future<void> deleteAccount() async {
    // Deletion is a privileged operation handled by an Edge Function using the
    // service role; the client only requests it.
    await _client.functions.invoke('delete-account');
    await signOut();
  }

  void dispose() {
    _sub.cancel();
    _out.close();
  }
}
