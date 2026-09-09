import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/config/env.dart';

/// Every tool logo on a page goes through the proxy, so what the URL carries
/// decides whether a card shows a real logo or falls back to a coloured
/// initial. The proxy tries the stored image first and the site's favicon
/// second, so the fallback domain is what rescues a logo URL that has rotted.

const _base = 'https://p.functions.supabase.co';

void main() {
  test('the stored logo URL is what the proxy is asked to fetch', () {
    final url = Env.buildProxyUrl(_base, 'https://acme.ai/logo.png');
    expect(url, startsWith('$_base/logo?url='));
    expect(url, contains(Uri.encodeComponent('https://acme.ai/logo.png')));
  });

  test('a website is reduced to the bare host the favicon services want', () {
    for (final site in [
      'https://www.acme.ai/pricing',
      'http://acme.ai',
      'acme.ai',
      'https://acme.ai/',
      '  https://www.acme.ai  ',
    ]) {
      expect(Env.logoDomainOf(site), 'acme.ai', reason: 'from "$site"');
    }
  });

  test('the fallback rides along on the proxy URL', () {
    final url = Env.buildProxyUrl(
      _base,
      'https://cdn.x/l.png',
      fallbackDomain: 'https://www.acme.ai/pricing',
    );
    expect(url, contains('&domain=acme.ai'));
  });

  test('nothing is sent when there is no website to fall back to', () {
    for (final site in [null, '', '   ', 'not a url at all']) {
      final url = Env.buildProxyUrl(
        _base,
        'https://cdn.x/l.png',
        fallbackDomain: site,
      );
      expect(url, isNot(contains('domain=')), reason: 'from "${site ?? ''}"');
    }
  });

  test('an already-proxied URL is not wrapped a second time', () {
    // Wrapping works, but spends two invocations to fetch one image.
    const proxied = '$_base/logo?domain=acme.ai';
    expect(Env.proxiedImage(proxied), proxied);
  });
}
