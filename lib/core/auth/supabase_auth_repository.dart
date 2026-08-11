import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/profile.dart';
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

  Profile _fallbackProfile(User user) => Profile(
        id: user.id,
        username: user.email?.split('@').first ?? 'user',
        displayName: (user.userMetadata?['display_name'] as String?) ??
            user.email?.split('@').first ??
            'User',
        avatarUrl: user.userMetadata?['avatar_url'] as String?,
        role: UserRole.user,
        createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
      );

  Future<Profile?> _loadProfile(String id) async {
    final row =
        await _client.from('profiles').select().eq('id', id).maybeSingle();
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
      final res = await _client.auth
          .signInWithPassword(email: email, password: password);
      return _afterAuth(res);
    } on AuthException catch (e) {
      throw LizException(e.message);
    }
  }

  @override
  Future<Profile> signUpWithEmail(
      String email, String password, String displayName) async {
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      return _afterAuth(res);
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
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<Profile> updateProfile({String? displayName, String? bio}) async {
    final id = currentUserId;
    if (id == null) throw const AuthRequiredException();
    final row = await _client
        .from('profiles')
        .update({
          if (displayName != null) 'display_name': displayName,
          if (bio != null) 'bio': bio,
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
