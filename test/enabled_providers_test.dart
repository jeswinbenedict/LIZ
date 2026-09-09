import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/auth/enabled_providers.dart';

/// The sheet offered Google and Apple unconditionally. Neither was enabled on
/// the project, so every tap dead-ended on Supabase's raw error JSON:
///   {"code":400,...,"msg":"Unsupported provider: provider is not enabled"}
/// A button that cannot succeed is worse than no button.

void main() {
  test('reports only what the project has enabled', () {
    const providers = EnabledAuthProviders({'email', 'google'});

    expect(providers.google, isTrue);
    expect(providers.apple, isFalse);
    expect(providers.has('github'), isFalse);
  });

  test('email alone offers no social buttons', () {
    // This is the live project's actual configuration.
    const providers = EnabledAuthProviders({'email'});

    expect(providers.hasSocial, isFalse,
        reason: 'an "or" divider with nothing above it reads as a missing button');
  });

  test('hasSocial is true as soon as one provider is enabled', () {
    expect(const EnabledAuthProviders({'email', 'apple'}).hasSocial, isTrue);
    expect(const EnabledAuthProviders({'email', 'google'}).hasSocial, isTrue);
  });

  test('the fallback offers nothing rather than guessing', () {
    // Used while the lookup is in flight and whenever it fails, so a network
    // problem degrades to the email form instead of to broken buttons.
    expect(EnabledAuthProviders.none.hasSocial, isFalse);
    expect(EnabledAuthProviders.none.google, isFalse);
    expect(EnabledAuthProviders.none.apple, isFalse);
  });
}
