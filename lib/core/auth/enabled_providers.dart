import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';

/// Which sign-in providers this Supabase project actually has enabled.
///
/// The app used to offer "Continue with Google" and "Continue with Apple"
/// unconditionally. Neither was enabled on the project, so tapping either left
/// Supabase's raw error JSON on screen:
///
///   {"code":400,"error_code":"validation_failed",
///    "msg":"Unsupported provider: provider is not enabled"}
///
/// `/auth/v1/settings` is public and reports exactly what is configured, so the
/// sheet can offer only what will work — and starts offering Google by itself
/// the moment it is switched on, with no release.
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

/// Resolves once per app run. Failures resolve to "no social providers" rather
/// than throwing: showing an email form is a working sign-in, while showing a
/// button that cannot succeed is not.
final enabledAuthProvidersProvider =
    FutureProvider<EnabledAuthProviders>((ref) async {
  if (!Env.useSupabase) return EnabledAuthProviders.none;

  final url = Uri.parse('${Env.supabaseUrl}/auth/v1/settings');
  try {
    final res = await http
        .get(url, headers: {'apikey': Env.supabaseAnonKey})
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return EnabledAuthProviders.none;

    final body = jsonDecode(res.body);
    final external = body is Map ? body['external'] : null;
    if (external is! Map) return EnabledAuthProviders.none;

    final enabled = <String>{
      for (final entry in external.entries)
        if (entry.value == true) entry.key.toString(),
    };
    return EnabledAuthProviders(enabled);
  } catch (_) {
    return EnabledAuthProviders.none;
  }
});
