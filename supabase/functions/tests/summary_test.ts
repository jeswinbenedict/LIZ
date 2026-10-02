import { assertEquals } from 'jsr:@std/assert@1';
import { NEWS_GROUNDING, parseBullets, summaryPrompt } from '../_shared/summary.ts';

// The backfill first ran with a prompt asking for a bare JSON array. Nothing
// parsed, so it reported "no usable bullets" for every tool and wrote nothing —
// a silent no-op that looked like a working job. These pin the shapes that must
// survive.

Deno.test('reads the documented {"bullets": [...]} shape', () => {
  assertEquals(
    parseBullets('{"bullets":["Edits video by transcript","Clones voices","Exports to Premiere"]}'),
    ['Edits video by transcript', 'Clones voices', 'Exports to Premiere'],
  );
});

Deno.test('reads a bare array, which models return despite the instruction', () => {
  assertEquals(parseBullets('["one","two"]'), ['one', 'two']);
});

Deno.test('survives prose and code fences around the JSON', () => {
  const reply = 'Sure! Here you go:\n```json\n{"bullets":["a","b"]}\n```\nHope that helps.';
  assertEquals(parseBullets(reply), ['a', 'b']);
});

Deno.test('caps at three bullets', () => {
  assertEquals(parseBullets('{"bullets":["a","b","c","d","e"]}').length, 3);
});

Deno.test('drops blank and non-string entries rather than storing them', () => {
  assertEquals(parseBullets('{"bullets":["good","   ",null,42,"also good"]}'), [
    'good',
    'also good',
  ]);
});

Deno.test('trims whitespace', () => {
  assertEquals(parseBullets('{"bullets":["  padded  "]}'), ['padded']);
});

Deno.test('returns nothing usable rather than throwing on junk', () => {
  // An empty result must stay empty: writing [] would mark the tool done and
  // leave it permanently without a summary.
  assertEquals(parseBullets('I cannot help with that.'), []);
  assertEquals(parseBullets(''), []);
  assertEquals(parseBullets('{"bullets": '), []);
  assertEquals(parseBullets('{"summary":"wrong key"}'), []);
});

// --- rate limiting ---------------------------------------------------------
// The backfill hit Groq's per-minute cap and dropped every row in the batch.
// An unattended run has nobody to notice, so the wait is honoured in-process.

Deno.test('retryAfterMs honours a seconds value', async () => {
  const { retryAfterMs } = await import('../_shared/ai.ts');
  assertEquals(retryAfterMs('7'), 7000);
});

Deno.test('retryAfterMs falls back when the header is missing or junk', async () => {
  const { retryAfterMs } = await import('../_shared/ai.ts');
  assertEquals(retryAfterMs(null), 4000);
  assertEquals(retryAfterMs('not-a-number'), 4000);
});

Deno.test('retryAfterMs never waits past a function lifetime', async () => {
  const { retryAfterMs } = await import('../_shared/ai.ts');
  assertEquals(retryAfterMs('600'), 20000);
});

Deno.test('a news quick take is held to what the snippet says', () => {
  const news = summaryPrompt({ title: 'T', description: 'D', kind: 'news' });
  assertEquals(news.endsWith(NEWS_GROUNDING), true);
  // Tool summaries are unchanged.
  assertEquals(
    summaryPrompt({ title: 'T', description: 'D' }),
    'Kind: tool\nTitle: T\nDescription: D',
  );
  // "Nothing to say" parses to no bullets, which counts against the row.
  assertEquals(parseBullets('{"bullets": []}'), []);
});
