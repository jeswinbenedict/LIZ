import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  cacheKey,
  cacheUse,
  FRESH_FOR_MS,
  hackerNewsFrom,
  STALE_UP_TO_MS,
} from '../tool-updates/logic.ts';

// Google News answered about half of tool-updates' calls from Supabase with
// 503 (4 of 8 tools, 28 September), and every page view spent part of GitHub's
// 60-an-hour budget. Answers are now cached, and Hacker News stands in when
// Google refuses.

const story = (title: string, extra: Record<string, unknown> = {}) => ({
  title,
  objectID: '42',
  url: 'https://example.com/a',
  created_at: '2026-09-20T10:00:00Z',
  ...extra,
});

Deno.test('only stories about the tool, by whole word in the title', () => {
  const items = hackerNewsFrom(
    {
      hits: [
        story('Midjourney Releasing v8.2'),
        story("Midjourney's First Acquisition"),
        story('Show HN: Midjourney API with webhooks'), // someone else's project
        story('Recursor: a new editor'), // part of a longer word
        story('Unrelated headline'),
      ],
    },
    'Midjourney',
  );
  assertEquals(items.map((i) => i.title), [
    'Midjourney Releasing v8.2',
    "Midjourney's First Acquisition",
  ]);
  assertEquals(items[0].source, 'Hacker News');
});

Deno.test('a name is matched literally, punctuation and all', () => {
  // Regex characters in a tool name must not become regex syntax.
  const items = hackerNewsFrom({ hits: [story('Why C++ tooling still lags'), story('C tooling')] }, 'C++');
  assertEquals(items.map((i) => i.title), ['Why C++ tooling still lags']);
});

Deno.test('a story without a link points at its discussion', () => {
  const [item] = hackerNewsFrom({ hits: [story('Suno v6 released', { url: null })] }, 'Suno');
  assertEquals(item.url, 'https://news.ycombinator.com/item?id=42');
});

Deno.test('junk in, nothing out', () => {
  assertEquals(hackerNewsFrom(null, 'Suno'), []);
  assertEquals(hackerNewsFrom({ hits: 'nope' }, 'Suno'), []);
  assertEquals(hackerNewsFrom({ hits: [story('Suno')] }, '  '), []);
});

Deno.test('a tool with a repository is cached by it, others by name', () => {
  assertEquals(cacheKey({ owner: 'Ollama', repo: 'ollama' }, 'x'), 'gh:ollama/ollama');
  assertEquals(cacheKey(null, '  Perplexity '), 'news:perplexity');
});

Deno.test('an answer is fresh for 12 hours, a fallback for a week', () => {
  const now = Date.parse('2026-09-28T12:00:00Z');
  const ago = (ms: number) => new Date(now - ms).toISOString();
  assertEquals(cacheUse(ago(60_000), now), 'fresh');
  assertEquals(cacheUse(ago(FRESH_FOR_MS + 1), now), 'fallback');
  assertEquals(cacheUse(ago(STALE_UP_TO_MS + 1), now), 'none');
  assertEquals(cacheUse(null, now), 'none');
  // A timestamp from the future is not trusted to be fresh.
  assertEquals(cacheUse(new Date(now + 60_000).toISOString(), now), 'none');
  assert(FRESH_FOR_MS < STALE_UP_TO_MS);
});
