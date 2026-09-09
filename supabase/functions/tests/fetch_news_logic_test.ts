import { assert, assertEquals } from 'jsr:@std/assert@1';
import { cleanTitle, decodeEntities, stripHtml } from '../fetch-news/logic.ts';

// Feeds encode punctuation in whichever form they please. Every string below
// reached the live News page looking broken before these rules existed.

Deno.test('decodes the numeric escapes that shipped raw to users', () => {
  assertEquals(
    decodeEntities('look up the definition of &#34;malicious compliance&#34;'),
    'look up the definition of "malicious compliance"',
  );
  assertEquals(decodeEntities('Instagram&#8217;s new logo'), 'Instagram’s new logo');
  assertEquals(decodeEntities('and so on&#8230;'), 'and so on…');
});

Deno.test('decodes named and hex escapes too', () => {
  assertEquals(decodeEntities('&quot;quoted&quot;'), '"quoted"');
  assertEquals(decodeEntities('&#x22;hex&#x22;'), '"hex"');
  assertEquals(decodeEntities('AT&amp;T &mdash; done'), 'AT&T — done');
});

Deno.test('leaves undecodable sequences intact rather than mangling them', () => {
  const input = '&#999999999999; &notarealentity; bare &';
  assertEquals(decodeEntities(input), input);
});

Deno.test('stripHtml removes real markup', () => {
  assertEquals(stripHtml('<p>Tags <b>stripped</b></p>'), 'Tags stripped');
  assertEquals(stripHtml('<script>alert(1)</script>hello'), 'alert(1) hello');
});

Deno.test('an encoded tag stays literal text, not markup', () => {
  // Stripping before decoding preserves an article's own "&lt;div&gt;" instead
  // of deleting it. The output is therefore plain text, never safe HTML —
  // callers must render it as text, which the Flutter client does.
  assertEquals(
    stripHtml('&lt;script&gt;alert(1)&lt;/script&gt;'),
    '<script>alert(1)</script>',
  );
});

Deno.test('stripHtml collapses whitespace and truncates long text', () => {
  assertEquals(stripHtml('a   \n  b'), 'a b');
  const long = stripHtml('x'.repeat(500));
  assertEquals(long.length, 298);
  assert(long.endsWith('…'));
});

Deno.test('cleanTitle decodes headlines, which stripHtml never saw', () => {
  // Titles bypassed the decoder entirely, so this was the most visible break.
  assertEquals(cleanTitle('This is Instagram&#8217;s new logo'), 'This is Instagram’s new logo');
  assertEquals(cleanTitle('  spaced   out  '), 'spaced out');
});

Deno.test('cleanTitle handles empty input', () => {
  assertEquals(cleanTitle(''), '');
});
