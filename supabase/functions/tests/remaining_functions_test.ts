import { assert, assertEquals } from 'jsr:@std/assert@1';
import { clampLimit, embedBatch, summarizeBatch } from '../_shared/batch.ts';
import { deleteCaller } from '../delete-account/logic.ts';
import { fcmMessage, isDeadToken, targetIds } from '../send-notification/logic.ts';
import {
  aboutTool,
  firstLine,
  newestFirst,
  newsFrom,
  releasesFrom,
  repoFrom,
} from '../tool-updates/logic.ts';

// The five functions that had no tests: delete-account, send-notification,
// tool-updates, embed-tools and summarize-tools. Each had its decisions pulled
// out of the request handler so they can be exercised here without a network.

// --- delete-account ---------------------------------------------------------

Deno.test('delete-account refuses a caller with no session', async () => {
  let deleted = false;
  const out = await deleteCaller({
    callerId: () => Promise.resolve(null),
    deleteUser: () => {
      deleted = true;
      return Promise.resolve(null);
    },
  });
  assertEquals(out.status, 401);
  assert(!deleted, 'nothing may be deleted without knowing who asked');
});

Deno.test('delete-account deletes exactly the caller', async () => {
  const deleted: string[] = [];
  const out = await deleteCaller({
    callerId: () => Promise.resolve('user-a'),
    deleteUser: (id) => {
      deleted.push(id);
      return Promise.resolve(null);
    },
  });
  assertEquals(out.status, 200);
  assertEquals(deleted, ['user-a']);
});

Deno.test('delete-account reports a failed deletion instead of claiming success', async () => {
  // On 26 September it failed for every account that had used the product
  // ("Database error deleting user"). The app must hear that, or it tells
  // someone their data is gone when none of it is.
  const out = await deleteCaller({
    callerId: () => Promise.resolve('user-a'),
    deleteUser: () => Promise.resolve('Database error deleting user'),
  });
  assertEquals(out.status, 400);
  assertEquals(out.body.error, 'Database error deleting user');
  assertEquals(out.body.data, null);
});

// --- send-notification ------------------------------------------------------

Deno.test('send-notification reads one user or many', () => {
  assertEquals(targetIds({ user_id: 'a' }), ['a']);
  assertEquals(targetIds({ user_ids: ['a', 'b'] }), ['a', 'b']);
  assertEquals(targetIds({}), []);
  // Junk in the list is dropped rather than sent to the database.
  assertEquals(targetIds({ user_ids: ['a', '', 7, null] }), ['a']);
});

Deno.test('an FCM message carries strings only, and a link on the web', () => {
  const m = fcmMessage('tok', {
    title: 'Price change',
    body: undefined,
    route: '/tool/t-1',
    data: { tool_id: 't-1', rank: 3 },
  }).message;
  assertEquals(m.token, 'tok');
  assertEquals(m.notification, { title: 'Price change', body: '' });
  // FCM rejects a message whose data holds anything but strings.
  assertEquals(m.data, { route: '/tool/t-1', tool_id: 't-1', rank: '3' });
  assertEquals(m.webpush?.fcm_options.link, '/tool/t-1');
});

Deno.test('an FCM message without a route has no web link', () => {
  const m = fcmMessage('tok', { title: 'Hi' }).message;
  assertEquals(m.webpush, undefined);
  assertEquals(m.data, { route: '' });
});

Deno.test('only a dead token is pruned, not an FCM outage', () => {
  assert(isDeadToken(404)); // unregistered
  assert(isDeadToken(400)); // invalid
  // Pruning on these would sign everyone out of push over a bad minute.
  for (const status of [401, 429, 500, 503]) assert(!isDeadToken(status), String(status));
});

// --- tool-updates -----------------------------------------------------------

Deno.test('a GitHub source URL names the repository', () => {
  assertEquals(repoFrom('https://github.com/ollama/ollama'), { owner: 'ollama', repo: 'ollama' });
  assertEquals(repoFrom('https://github.com/a/b.git#readme'), { owner: 'a', repo: 'b' });
  assertEquals(repoFrom(undefined, 'n8n'), { owner: 'n8n-io', repo: 'n8n' });
  assertEquals(repoFrom('https://acme.ai', 'acme'), null);
});

Deno.test('a release note is its first line of prose', () => {
  assertEquals(firstLine('## What changed\n\n- Faster startup'), 'What changed');
  assertEquals(firstLine('```\ncode\n```\nReal text'), 'Real text');
  assertEquals(firstLine(''), null);
  assertEquals(firstLine('x'.repeat(300))?.length, 160);
});

Deno.test('drafts are not releases', () => {
  const items = releasesFrom([
    { name: 'v2', html_url: 'u2', published_at: '2026-09-02T00:00:00Z', body: 'New' },
    { name: 'v3', html_url: 'u3', draft: true },
    { name: '  ', tag_name: 'v1', html_url: 'u1', published_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(items.map((i) => i.title), ['v2', 'v1']);
  assertEquals(releasesFrom({ message: 'rate limited' }), []);
});

const RSS = `<rss><channel>
<item><title>Acme launches agents - The Verge</title><link>https://n/1</link>
<pubDate>Tue, 22 Sep 2026 10:00:00 GMT</pubDate><source url="x">The Verge</source></item>
<item><title><![CDATA[Acme &amp; friends ship &#39;v2&#39;]]></title><link>https://n/2</link>
<pubDate>not a date</pubDate></item>
<item><title></title><link>https://n/3</link></item>
</channel></rss>`;

Deno.test('news items are cleaned, and one bad date does not sink the rest', () => {
  // A malformed pubDate used to throw inside the loop, which the handler
  // caught by returning nothing — so one bad item blanked "What's new".
  const items = newsFrom(RSS);
  assertEquals(items.length, 2);
  assertEquals(items[0].title, 'Acme launches agents');
  assertEquals(items[0].source, 'The Verge');
  assertEquals(items[0].published_at, '2026-09-22T10:00:00.000Z');
  assertEquals(items[1].title, "Acme & friends ship 'v2'");
  assertEquals(items[1].published_at, null);
  assertEquals(items[1].source, 'Google News');
});

Deno.test('updates are newest first, undated last', () => {
  const sorted = newestFirst([
    { title: 'old', note: null, url: '', source: '', published_at: '2026-01-01T00:00:00Z' },
    { title: 'none', note: null, url: '', source: '', published_at: null },
    { title: 'new', note: null, url: '', source: '', published_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(sorted.map((i) => i.title), ['new', 'old', 'none']);
});

// --- embed-tools / summarize-tools -----------------------------------------

Deno.test('a batch size is clamped to what a worker survives', () => {
  assertEquals(clampLimit({ limit: 3 }, 5, 10), 3);
  assertEquals(clampLimit({ limit: 500 }, 5, 10), 10);
  assertEquals(clampLimit({}, 5, 10), 5);
  assertEquals(clampLimit(null, 5, 10), 5);
  // A negative limit used to pass straight through to the query.
  assertEquals(clampLimit({ limit: -4 }, 5, 10), 5);
  assertEquals(clampLimit({ limit: 'lots' }, 5, 10), 5);
});

Deno.test('only an empty summary counts against the row', async () => {
  const noted: string[] = [];
  const saved: string[] = [];
  const result = await summarizeBatch(
    [
      { id: 'good', name: 'Good', tagline: 'Does a thing' },
      { id: 'empty', name: 'Empty', description: '![badge]' },
      { id: 'limited', name: 'Limited' },
    ],
    {
      summarize: ({ title }) => {
        if (title === 'Good') return Promise.resolve(['One', 'Two']);
        if (title === 'Empty') return Promise.resolve([]);
        return Promise.reject(new Error('429 rate limited'));
      },
      save: (id) => {
        saved.push(id);
        return Promise.resolve(null);
      },
      noteAttempt: (id) => {
        noted.push(id);
        return Promise.resolve();
      },
    },
  );
  assertEquals(result.summarized, 1);
  assertEquals(saved, ['good']);
  // The rate-limited row is not its own fault; only the empty one is noted.
  assertEquals(noted, ['empty']);
  assertEquals(result.failures.length, 2);
});

Deno.test('a failed save is a failure, not a summary', async () => {
  const result = await summarizeBatch([{ id: 'a', name: 'A' }], {
    summarize: () => Promise.resolve(['x']),
    save: () => Promise.resolve('permission denied'),
    noteAttempt: () => Promise.resolve(),
  });
  assertEquals(result.summarized, 0);
  assertEquals(result.failures, ['A: permission denied']);
});

Deno.test('embedding skips rows with nothing to embed and survives one failure', async () => {
  const embeddedIds: string[] = [];
  const result = await embedBatch(
    [{ id: 'a', t: 'alpha' }, { id: 'blank', t: '' }, { id: 'b', t: 'boom' }, { id: 'c', t: 'gamma' }],
    {
      text: (tool) => tool.t,
      embed: (text) =>
        text === 'boom' ? Promise.reject(new Error('WORKER_RESOURCE_LIMIT')) : Promise.resolve([0.1]),
      save: (id) => {
        embeddedIds.push(id);
        return Promise.resolve(null);
      },
    },
  );
  assertEquals(result.embedded, 2);
  assertEquals(embeddedIds, ['a', 'c']);
  assertEquals(result.failures.length, 1);
  assert(result.failures[0].startsWith('b:'));
});

Deno.test('tool-updates keeps only headlines that name the tool, once per story', () => {
  const item = (title: string, source = 'TechCrunch') => ({
    title, note: null, url: `https://x/${encodeURIComponent(title)}`, source, published_at: null,
  });
  const kept = aboutTool([
    item('ElevenLabs Doubles Valuation to $22 Billion'),
    // Matched by Google News on the article body, not the headline (1 Oct).
    item('Ramp Launches in the UK', 'PR Newswire'),
    item('ElevenLabs launches Eleven v4'),
    item('ElevenLabs Launches Eleven V4!'),
    item('v2.3.0', 'GitHub Releases'),
  ], 'ElevenLabs');
  assertEquals(kept.map((i) => i.title), [
    'ElevenLabs Doubles Valuation to $22 Billion',
    'ElevenLabs launches Eleven v4',
    'v2.3.0',
  ]);
});
