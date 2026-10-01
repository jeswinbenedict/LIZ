import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

/// Which sign-in providers to offer.
///
/// The app used to offer "Continue with Google" and "Continue with Apple"
/// unconditionally. Neither was enabled on the project, so tapping either left
/// Supabase's raw error JSON on screen:
///
///   {"code":400,"error_code":"validation_failed",
///    "msg":"Unsupported provider: provider is not enabled"}
///
/// So the sheet offers only providers the build says are configured.
class EnabledAuthProviders {
  const EnabledAuthProviders(this._names);

  final Set<String> _names;

  static const none = EnabledAuthProviders(<String>{});

  bool has(String provider) => _names.contains(provider);

  bool get google => has('google');
  bool get apple => has('apple');

  /// True when at least one provider other than email is offered, which is what
  /// decides whether the "or" divider above the email form earns its place.
  bool get hasSocial => google || apple;
}

/// The social sign-in buttons to offer, from the build:
/// `--dart-define=AUTH_PROVIDERS=google,apple`. Defaults to Google, the one
/// that needs nothing beyond switching it on in the Firebase console.
///
/// Firebase, unlike Supabase, has no public endpoint that lists a project's
/// enabled providers, so this cannot be looked up at run time. A provider
/// listed here but not switched on fails with a plain "isn't available yet"
/// (see firebase_errors.dart) rather than raw JSON.
const _configured = String.fromEnvironment(
  'AUTH_PROVIDERS',
  defaultValue: 'google',
);

EnabledAuthProviders providersFrom(String csv) => EnabledAuthProviders({
  'email',
  for (final p in csv.split(','))
    if (p.trim().isNotEmpty) p.trim().toLowerCase(),
});

final enabledAuthProvidersProvider = FutureProvider<EnabledAuthProviders>((
  ref,
) async {
  if (!Env.useSupabase) return EnabledAuthProviders.none;
  return providersFrom(_configured);
});
