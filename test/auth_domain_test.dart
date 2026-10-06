import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/firebase/firebase_app.dart';

/// Google sign-in's helper pages come from Liz's own address on the live
/// site, so browsers that block third-party storage (Brave on 6 October 2026)
/// do not break the popup. Only a host whose relay Google's sign-in client
/// knows about may use itself; anything else would fail with
/// redirect_uri_mismatch, so it keeps Firebase's address.
void main() {
  test('the live site signs in through its own address', () {
    expect(authDomainFor('liz-cfp.pages.dev'), 'liz-cfp.pages.dev');
  });

  test('previews and local builds keep Firebase\'s address', () {
    for (final host in [
      'abc123.liz-cfp.pages.dev',
      'localhost',
      '127.0.0.1',
      '',
    ]) {
      expect(authDomainFor(host), firebaseAuthDomain, reason: host);
    }
  });
}
