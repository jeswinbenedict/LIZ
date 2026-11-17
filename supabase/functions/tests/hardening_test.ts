// Regression tests for the issues CodeQL found after the repository went
// public (SECURITY_AUDIT.md): error replies that carried their cause,
// regular expressions that backtracked on hostile input, and a decoder that
// unescaped twice.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { failure } from '../_shared/cors.ts';
import { citations } from '../_shared/repo/ask.ts';
import { readmeIntro } from '../_shared/repo/report.ts';
import { decodeXml } from '../tool-updates/logic.ts';

Deno.test('failure() answers without the cause, and logs it', async () => {
  const logged: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(...args);
  try {
    const err = new Error('relation "secret_table" does not exist at line 3');
    const res = failure('ask-liz', err);
    assertEquals(res.status, 500);
    const body = await res.json();
    assertEquals(body.data, null);
    assert(!JSON.stringify(body).includes('secret_table'));
    assert(logged.some((l) => String(l).includes('secret_table')), 'the cause is logged');

    const client = await failure('fetch-tools', { message: 'duplicate key value violates "tools_pkey"' }, 400).json();
    assert(!JSON.stringify(client).includes('tools_pkey'));
  } finally {
    console.error = original;
  }
});

Deno.test('citations() still reads nested paths', () => {
  const chunks = [{ path: 'lib/app/router.dart', start: 1, end: 40, text: '' }];
  assertEquals(citations('See [lib/app/router.dart:12] and [lib/app/router.dart:99].', chunks), [
    { path: 'lib/app/router.dart', line: 12 },
  ]);
});

Deno.test('citations() stays fast on a long unclosed citation', () => {
  const hostile = '[' + 'a/'.repeat(50_000) + 'a';
  const started = performance.now();
  assertEquals(citations(hostile, []), []);
  assert(performance.now() - started < 1000, 'linear time');
});

Deno.test('readmeIntro() leaves no angle brackets behind', () => {
  const intro = readmeIntro('<<script>alert(1)</script>A tool that does a useful thing for people every day.');
  assert(intro === null || !/[<>]/.test(intro), String(intro));
});

Deno.test('decodeXml() unescapes once', () => {
  assertEquals(decodeXml('a &amp;lt;b&amp;gt; &amp; c'), 'a &lt;b&gt; & c');
  assertEquals(decodeXml('&lt;b&gt; &quot;x&quot; &#39;y&#39; &#65;'), '<b> "x" \'y\' A');
  assertEquals(decodeXml('<![CDATA[R&D]]>'), 'R&D');
});
