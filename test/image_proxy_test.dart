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

  test('a tool with no stored logo is looked up by its domain', () {
    expect(
      Env.buildDomainLogoUrl(_base, 'https://www.spiteware.ai/about'),
      '$_base/logo?domain=spiteware.ai',
    );
  });

  test('a shared host is not taken for the tool’s own', () {
    // Every repository would wear GitHub's mark, and every Cloud Run app
    // Google's — a wrong logo reads as a real one, a letter tile does not.
    for (final site in [
      'https://github.com/acme/tool',
      'https://raw.githubusercontent.com/a/b/paper.pdf',
      'https://search-1835.asia-southeast1.run.app',
      'https://www.producthunt.com/products/x',
      null,
      'not a url at all',
    ]) {
      expect(Env.buildDomainLogoUrl(_base, site), isNull, reason: '$site');
    }
  });

  test('logos in our own Storage are not sent through the proxy', () {
    const base = 'https://ref.supabase.co';
    expect(
      Env.isOwnStorageIn(
        base,
        'https://ref.supabase.co/storage/v1/object/public/logos/t-1.webp',
      ),
      isTrue,
    );
    expect(
      Env.isOwnStorageIn(
        base,
        'https://other.supabase.co/storage/v1/object/public/x',
      ),
      isFalse,
    );
    expect(
      Env.isOwnStorageIn(
        '',
        'https://ref.supabase.co/storage/v1/object/public/x',
      ),
      isFalse,
    );
  });
}
