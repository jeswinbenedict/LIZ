import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkTargetUrl, isAllowedImageType, MAX_IMAGE_BYTES } from '../logo/logic.ts';

/// The proxy fetches a caller-supplied URL and returns the bytes with
/// Access-Control-Allow-Origin: *. Unguarded that is an open relay — anyone on
/// the internet could launder requests through this project, and reach hosts
/// only the server can see.

Deno.test('allows ordinary public image URLs', () => {
  for (const url of [
    'https://acme.ai/logo.png',
    'http://example.com/favicon.ico',
    'https://cdn.example.co.uk/a/b/icon.svg?v=2',
  ]) {
    assert(checkTargetUrl(url).ok, `${url} should be allowed`);
  }
});

Deno.test('refuses cloud metadata, the classic SSRF target', () => {
  const check = checkTargetUrl('http://169.254.169.254/latest/meta-data/');
  assertEquals(check.ok, false);
});

Deno.test('refuses loopback and private ranges', () => {
  for (const url of [
    'http://localhost:8000/admin',
    'http://127.0.0.1/',
    'http://10.0.0.5/secret',
    'http://192.168.1.1/',
    'http://172.16.4.4/',
    'http://[::1]/',
  ]) {
    assertEquals(checkTargetUrl(url).ok, false, `${url} should be refused`);
  }
});

Deno.test('refuses hostnames that only resolve inside a network', () => {
  assertEquals(checkTargetUrl('http://metadata.google.internal/').ok, false);
  assertEquals(checkTargetUrl('http://printer.local/').ok, false);
  assertEquals(checkTargetUrl('http://db.internal/').ok, false);
});

Deno.test('refuses schemes an image proxy has no business reading', () => {
  for (const url of ['file:///etc/passwd', 'data:text/html,<script>', 'gopher://x/']) {
    assertEquals(checkTargetUrl(url).ok, false, `${url} should be refused`);
  }
});

Deno.test('refuses input that is not a URL at all', () => {
  assertEquals(checkTargetUrl('').ok, false);
  assertEquals(checkTargetUrl('not a url').ok, false);
});

Deno.test('a public address that merely looks private is still allowed', () => {
  // 11.x and 172.32.x sit outside the private ranges.
  assert(checkTargetUrl('http://11.0.0.1/logo.png').ok);
  assert(checkTargetUrl('http://172.32.0.1/logo.png').ok);
});

Deno.test('only image responses are relayed', () => {
  assert(isAllowedImageType('image/png'));
  assert(isAllowedImageType('image/svg+xml; charset=utf-8'));
  // An HTML or JSON body means the caller is fetching something else.
  assertEquals(isAllowedImageType('text/html'), false);
  assertEquals(isAllowedImageType('application/json'), false);
  assertEquals(isAllowedImageType(null), false);
});

Deno.test('the size cap is bounded to something logo-shaped', () => {
  assert(MAX_IMAGE_BYTES > 0 && MAX_IMAGE_BYTES <= 10 * 1024 * 1024);
});
