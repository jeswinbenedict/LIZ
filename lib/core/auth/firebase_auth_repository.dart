import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../shared/models/profile.dart';
import '../config/env.dart';
import '../errors.dart';
import '../firebase/firebase_app.dart';
import '../telemetry/crash_reporter.dart';
import 'auth_repository.dart';
import 'firebase_errors.dart';

/// The code in a Firebase password-reset link, or null when [uri] is not one.
String? passwordResetCodeIn(Uri uri) {
  final q = uri.queryParameters;
  final code = q['oobCode'];
  return q['mode'] == 'resetPassword' && code != null && code.isNotEmpty
      ? code
      : null;
}

/// Sign-in through Firebase Authentication; the profile and everything else
/// in Supabase (migration 0055).
///
/// After every sign-in, and on each return visit, the app calls the
/// firebase-session function with the Firebase ID token. That finds or
/// creates the Liz user the account signs in as and gives the account the
/// claims Supabase needs (`role: authenticated`, `liz_uid`). Supabase reads
/// the token on every request through Supabase.initialize's `accessToken`.
///
/// Firebase is started only when needed — a sign-in, or a browser that had a
/// session last time (remembered in [_sessionHint]) — so a first-time visitor
/// downloads none of it.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._client) {
    unawaited(_resumeIfRemembered());
  }

  final SupabaseClient _client;
  final _out = StreamController<Profile?>.broadcast();
  StreamSubscription<User?>? _sub;
  Profile? _current;
  bool _listening = false;

  /// Display name typed at sign-up, for the session call that creates the
  /// profile.
  String? _pendingName;

  /// A sign-in waiting for its authenticator code.
  MultiFactorResolver? _resolver;

  /// An authenticator being set up, waiting for its first code.
  TotpSecret? _pendingSecret;

  static const _sessionHint = 'liz.firebase_session';
  static const _linkEmail = 'liz.sign_in_link_email';
  static const _pendingSetupId = 'pending';

  @override
  Profile? get currentProfile => _current;

  @override
  String? get currentUserId => _current?.id;

  @override
  Stream<Profile?> authStateChanges() => _out.stream;

  // --- starting Firebase -----------------------------------------------------

  Future<void> _resumeIfRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final link = Uri.base.toString();
      final remembered = prefs.getBool(_sessionHint) == true;
      final arrivingWithLink =
          Uri.base.queryParameters['mode'] == 'signIn' &&
          Uri.base.queryParameters.containsKey('oobCode');
      if (!remembered && !arrivingWithLink) return;
      await _auth();
      if (arrivingWithLink) await _completeLinkSignIn(link, prefs);
    } catch (e) {
      debugPrint('Resuming the session failed: $e');
    }
  }

  /// FirebaseAuth, started and listened to.
  Future<FirebaseAuth> _auth() async {
    if (!await ensureFirebase()) {
      throw const LizException('Sign-in is unavailable right now. Try again.');
    }
    final auth = FirebaseAuth.instance;
    if (!_listening) {
      _listening = true;
      _sub = auth.authStateChanges().listen(_onUser);
      auth.idTokenChanges().listen((user) async {
        // Realtime keeps its own copy of the token; hand it each new one.
        final token = await user?.getIdToken();
        _client.realtime.setAuth(token);
      });
    }
    return auth;
  }

  Future<void> _onUser(User? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.setBool(_sessionHint, false);
      _set(null);
      return;
    }
    await prefs.setBool(_sessionHint, true);
    try {
      await _sync(user);
    } on LizException {
      // A returning session that cannot become a Liz session (its address
      // needs confirming) signs out quietly; sign-in explains why.
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Session sync failed: $e');
    }
  }

  void _set(Profile? profile) {
    _current = profile;
    CrashReporter.userId = profile?.id;
    _out.add(profile);
  }

  Future<Profile>? _syncing;
  String? _syncingUid;

  /// Turns the Firebase user into a Liz session, and returns its profile.
  ///
  /// A sign-in and the auth listener both arrive here for the same user; they
  /// share one call rather than racing two.
  Future<Profile> _sync(User user) {
    if (_syncing != null && _syncingUid == user.uid) return _syncing!;
    _syncingUid = user.uid;
    return _syncing = _syncOnce(user).whenComplete(() {
      _syncing = null;
      _syncingUid = null;
    });
  }

  Future<Profile> _syncOnce(User user) async {
    final res = await _client.functions.invoke(
      'firebase-session',
      body: {'display_name': ?_pendingName},
    );
    _pendingName = null;
    final data = (res.data is Map ? res.data['data'] : null) as Map?;
    if (data == null) {
      throw const LizException('Could not finish signing in. Try again.');
    }
    if (data['needs_verification'] == true) {
      try {
        await user.sendEmailVerification();
      } catch (_) {}
      throw const LizException(
        'This email already has a Liz account. We\'ve sent you a link — '
        'confirm the address, then sign in again to carry on with it.',
      );
    }
    if (data['refresh'] == true) {
      // The new claims are in the next token, not this one.
      await user.getIdToken(true);
    }
    final id = data['user_id'] as String;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    final profile = row == null
        ? _fallbackProfile(user, id)
        : Profile.fromJson(row);
    _set(profile);
    return profile;
  }

  Profile _fallbackProfile(User user, String id) => Profile(
    id: id,
    username: user.email?.split('@').first ?? 'user',
    displayName: user.displayName ?? user.email?.split('@').first ?? 'User',
    avatarUrl: user.photoURL,
    role: UserRole.user,
    createdAt: user.metadata.creationTime ?? DateTime.now(),
  );

  /// Runs a Firebase call, turning its errors into ones a person can read.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthMultiFactorException catch (e) {
      _resolver = e.resolver;
      throw const TwoStepRequiredException();
    } on FirebaseAuthException catch (e) {
      throw LizException(authErrorMessage(e.code));
    }
  }

  Future<Profile> _signedIn(UserCredential credential) async {
    final user = credential.user;
    if (user == null) throw const LizException('Sign-in failed.');
    return _sync(user);
  }

  // --- signing in --------------------------------------------------------------

  @override
  Future<Profile> signInWithEmail(String email, String password) async {
    final auth = await _auth();
    final cred = await _guard(
      () => auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    return _signedIn(cred);
  }

  @override
  Future<Profile> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final auth = await _auth();
    _pendingName = displayName;
    final cred = await _guard(
      () => auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    final user = cred.user;
    if (user != null) {
      unawaited(user.updateDisplayName(displayName).catchError((Object _) {}));
      // Confirming the address is not required to use Liz, but it is what
      // lets an account be linked or recovered later.
      unawaited(user.sendEmailVerification().catchError((Object _) {}));
    }
    return _signedIn(cred);
  }

  @override
  Future<void> sendMagicLink(String email) async {
    final auth = await _auth();
    final origin = Env.currentOrigin;
    if (origin.isEmpty) {
      throw const LizException('Email links work in the web app only.');
    }
    await _guard(
      () => auth.sendSignInLinkToEmail(
        email: email.trim(),
        actionCodeSettings: ActionCodeSettings(
          url: '$origin/',
          handleCodeInApp: true,
        ),
      ),
    );
    // The link must be opened with the same address; remember it for when
    // it comes back to this browser.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_linkEmail, email.trim());
  }

  Future<void> _completeLinkSignIn(String link, SharedPreferences prefs) async {
    final auth = FirebaseAuth.instance;
    if (!auth.isSignInWithEmailLink(link)) return;
    final email = prefs.getString(_linkEmail);
    // Opened on another device: there is no address to pair it with, and
    // asking for one here is a phishing pattern. The sign-in sheet still
    // works with a password.
    if (email == null) return;
    await _guard(() => auth.signInWithEmailLink(email: email, emailLink: link));
    await prefs.remove(_linkEmail);
  }

  @override
  Future<Profile> signInWithGoogle() async {
    final auth = await _auth();
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    return _signedIn(await _guard(() => auth.signInWithPopup(provider)));
  }

  @override
  Future<Profile> signInWithApple() async {
    final auth = await _auth();
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    return _signedIn(await _guard(() => auth.signInWithPopup(provider)));
  }

  @override
  Future<Profile> signInAsDemo() =>
      throw const LizException('Demo sign-in is only available in mock mode.');

  @override
  Future<Profile> completeTwoStepSignIn(String code) async {
    final resolver = _resolver;
    if (resolver == null) {
      throw const LizException('Sign in again to enter a code.');
    }
    final hint = resolver.hints.whereType<TotpMultiFactorInfo>().firstOrNull;
    if (hint == null) {
      throw const LizException(
        'This account\'s second step is not an authenticator app.',
      );
    }
    final cred = await _guard(() async {
      final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(
        hint.uid,
        code.trim(),
      );
      return resolver.resolveSignIn(assertion);
    });
    _resolver = null;
    return _signedIn(cred);
  }

  // --- passwords ---------------------------------------------------------------

  @override
  Future<void> sendPasswordReset(String email) async {
    final auth = await _auth();
    try {
      // Firebase sends the email and hosts the page that sets the password.
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Rate limiting and a malformed address are worth passing on: neither
      // says whether an account exists. Anything else is swallowed on
      // purpose (see the interface).
      if (e.code == 'too-many-requests' || e.code == 'invalid-email') {
        throw LizException(authErrorMessage(e.code));
      }
    }
  }

  /// The reset code when Firebase's emails are pointed at Liz's own
  /// /reset-password page (Firebase console → Templates → custom action URL).
  static String? get resetCode => passwordResetCodeIn(Uri.base);

  @override
  Future<void> updatePassword(String newPassword) async {
    final auth = await _auth();
    final code = resetCode;
    if (code != null) {
      await _guard(
        () => auth.confirmPasswordReset(code: code, newPassword: newPassword),
      );
      return;
    }
    final user = auth.currentUser;
    if (user == null) throw const AuthRequiredException();
    await _guard(() => user.updatePassword(newPassword));
  }

  @override
  Future<void> signOut() async {
    if (firebaseStarted) await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionHint, false);
    _set(null);
  }

  // --- the profile ---------------------------------------------------------------

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
    final profile = Profile.fromJson(row);
    _set(profile);
    return profile;
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
    // The function deletes the profile, everything tied to it, and the
    // Firebase account itself, using the service role.
    await _client.functions.invoke('delete-account');
    await signOut();
  }

  // --- two-step verification -----------------------------------------------------

  @override
  Future<TwoStep> twoStep() async {
    final user = (await _auth()).currentUser;
    if (user == null) throw const AuthRequiredException();
    final result = await user.getIdTokenResult();
    final firebase = result.claims?['firebase'];
    if (firebase is Map && firebase['sign_in_second_factor'] != null) {
      return const TwoStep(TwoStepStatus.verified);
    }
    final factors = await user.multiFactor.getEnrolledFactors();
    final totp = factors.whereType<TotpMultiFactorInfo>().firstOrNull;
    if (totp != null) {
      return TwoStep(TwoStepStatus.needsCode, factorId: totp.uid);
    }
    return const TwoStep(TwoStepStatus.needsSetup);
  }

  @override
  Future<TotpSetup> startTwoStepSetup() async {
    final user = (await _auth()).currentUser;
    if (user == null) throw const AuthRequiredException();
    return _guard(() async {
      final session = await user.multiFactor.getSession();
      final secret = await TotpMultiFactorGenerator.generateSecret(session);
      _pendingSecret = secret;
      final uri = await secret.generateQrCodeUrl(
        accountName: user.email,
        issuer: 'Liz',
      );
      return TotpSetup(
        factorId: _pendingSetupId,
        uri: uri,
        secret: secret.secretKey,
      );
    });
  }

  @override
  Future<void> verifyTwoStep(String factorId, String code) async {
    final user = (await _auth()).currentUser;
    if (user == null) throw const AuthRequiredException();
    final secret = _pendingSecret;
    if (factorId != _pendingSetupId || secret == null) {
      // An authenticator already set up is checked when signing in, not
      // here: Firebase asks for the code as part of the sign-in itself.
      throw const LizException(
        'Sign out and sign in again — you\'ll be asked for the code from '
        'your authenticator app.',
      );
    }
    await _guard(() async {
      final assertion =
          await TotpMultiFactorGenerator.getAssertionForEnrollment(
            secret,
            code.trim(),
          );
      await user.multiFactor.enroll(
        assertion,
        displayName: 'Liz authenticator',
      );
    });
    _pendingSecret = null;
    // The upgraded session is in the next token.
    await user.getIdToken(true);
    // Idempotent, and only effective for a moderator who has passed a code.
    try {
      await _client.rpc<dynamic>('require_moderator_mfa');
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _out.close();
  }
}
