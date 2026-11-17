import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth/auth_repository.dart';
import '../shared/widgets/liz_mark.dart';
import 'theme.dart';

/// Liz is for signed-in people: every page sends a signed-out visitor to
/// sign in first, and back to the page they asked for afterwards. These stay
/// open — signing in, getting back into an account, and the documents a
/// person should be able to read before agreeing to anything.
const publicPaths = {
  '/signin',
  '/forgot-password',
  '/reset-password',
  '/privacy',
  '/terms',
};

/// Shown while a returning visitor's session is restored, so they see a
/// moment of Liz rather than a flash of the sign-in form.
const startingPath = '/starting';

/// The welcome a new account opens on: interests, then alerts.
const welcomePath = '/welcome';

/// Set while an account is being created, so the first page after it is the
/// welcome rather than Discover. Cleared when the welcome is finished or
/// skipped, and when creating the account fails.
final welcomePending = ValueNotifier<bool>(false);

/// Where a navigation to [location] should go instead, or null to let it be.
///
/// [restored] is false until the session a returning visitor left behind has
/// been restored or found missing: until then, no profile does not yet mean
/// signed out.
String? authRedirect({
  required Uri location,
  required bool restored,
  required bool signedIn,
  bool welcome = false,
}) {
  final path = location.path;
  if (publicPaths.contains(path) && path != '/signin') return null;

  if (!restored) {
    if (path == startingPath || path == '/signin') return null;
    return _with(startingPath, location);
  }

  final from = safeReturnPath(location.queryParameters['from']);
  if (!signedIn) {
    if (path == '/signin') return null;
    if (path == startingPath) return _with('/signin', from);
    return _with('/signin', location);
  }

  // Signed in: the sign-in and starting pages have nothing left to do. A
  // new account goes by way of the welcome.
  if (path == '/signin' || path == startingPath) {
    if (welcome) return _with(welcomePath, from);
    return from?.toString() ?? '/';
  }
  return null;
}

/// [base] carrying where to go next as `?from=`, unless that is the home page.
String _with(String base, Uri? next) {
  if (next == null) return base;
  final target = next.toString();
  if (target == '/' || target.isEmpty) return base;
  return Uri(path: base, queryParameters: {'from': target}).toString();
}

/// A `from` value that is a path inside Liz, or null. Anything else — an
/// absolute URL, `//elsewhere.com` — would make the sign-in page a way to send
/// someone off the site after they trust it with a password.
Uri? safeReturnPath(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/') || raw.startsWith('//') || raw.contains('\\')) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (publicPaths.contains(uri.path) ||
      uri.path == startingPath ||
      uri.path == welcomePath) {
    return null;
  }
  return uri;
}

/// What the router listens to: whether the session has been restored, and
/// whether someone is signed in.
class AuthGate extends ChangeNotifier {
  AuthGate(AuthRepository auth) : _signedIn = auth.currentProfile != null {
    _sub = auth.authStateChanges().listen((profile) {
      final now = profile != null;
      if (now != _signedIn) {
        _signedIn = now;
        notifyListeners();
      }
    });
    auth.restored.whenComplete(() {
      _restored = true;
      _signedIn = auth.currentProfile != null;
      notifyListeners();
    });
  }

  late final StreamSubscription<Object?> _sub;
  bool _restored = false;
  bool _signedIn;

  bool get restored => _restored;
  bool get signedIn => _signedIn;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// The moment between opening Liz and knowing who is there: the mark, and a
/// quiet line that moves under it. It fades in, so a session restored in a
/// blink shows nothing at all.
class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Scaffold(
      body: Center(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: 'Starting Liz',
          child: ExcludeSemantics(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: LizMotion.of(
                context,
                const Duration(milliseconds: 600),
              ),
              curve: const Interval(0.4, 1, curve: Curves.easeOut),
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LizMark(size: 44),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 96,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: p.textSecondary,
                      backgroundColor: p.hairline,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
