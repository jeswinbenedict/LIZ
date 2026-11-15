// The fallback provider: tried only when the first fails to answer, never
// for an answer that is merely short, and both failures reported together.
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { AiCredentialsError, completeWith, type Provider, providersFrom } from '../_shared/ai.ts';

const primary: Provider = { name: 'primary', baseUrl: 'https://a.test/v1', model: 'm1', apiKey: 'k1' };
const fallback: Provider = { name: 'fallback', baseUrl: 'https://b.test/v1', model: 'm2', apiKey: 'k2' };
const noWait = () => Promise.resolve();

function reply(text: string): Response {
  return new Response(JSON.stringify({ choices: [{ message: { content: text } }] }), { status: 200 });
}

/// A fetch that answers per host and records which hosts were asked.
function fakeFetch(byHost: Record<string, () => Response>) {
  const asked: string[] = [];
  const fn = ((input: string | URL | Request) => {
    const host = new URL(String(input)).host;
    asked.push(host);
    return Promise.resolve(byHost[host]());
  }) as typeof fetch;
  return { fn, asked };
}

Deno.test('the fallback is configured only when all three settings are set', () => {
  const env = (vars: Record<string, string>) => (k: string) => vars[k];
  assertEquals(providersFrom(env({ AI_API_KEY: 'k' })).map((p) => p.name), ['primary']);
  assertEquals(
    providersFrom(env({ AI_API_KEY: 'k', AI_FALLBACK_BASE_URL: 'https://b/v1/', AI_FALLBACK_MODEL: 'm' }))
      .map((p) => p.name),
    ['primary'],
  );
  const both = providersFrom(env({
    AI_API_KEY: 'k',
    AI_FALLBACK_BASE_URL: 'https://b/v1/',
    AI_FALLBACK_MODEL: 'm',
    AI_FALLBACK_API_KEY: 'k2',
  }));
  assertEquals(both.map((p) => p.name), ['primary', 'fallback']);
  assertEquals(both[1].baseUrl, 'https://b/v1');
  // A fallback alone still works when the primary has no key.
  assertEquals(
    providersFrom(env({ AI_FALLBACK_BASE_URL: 'https://b', AI_FALLBACK_MODEL: 'm', AI_FALLBACK_API_KEY: 'k' }))
      .map((p) => p.name),
    ['fallback'],
  );
});

Deno.test('a healthy primary is the only one asked', async () => {
  const f = fakeFetch({ 'a.test': () => reply('from a'), 'b.test': () => reply('from b') });
  assertEquals(await completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait), 'from a');
  assertEquals(f.asked, ['a.test']);
});

Deno.test('a retired model (404) falls through to the fallback', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('model does not exist', { status: 404 }),
    'b.test': () => reply('from b'),
  });
  assertEquals(await completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait), 'from b');
  assertEquals(f.asked, ['a.test', 'b.test']);
});

Deno.test('rate limits are waited out before falling through', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('slow down', { status: 429, headers: { 'retry-after': '1' } }),
    'b.test': () => reply('from b'),
  });
  assertEquals(await completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait), 'from b');
  assertEquals(f.asked.filter((h) => h === 'a.test').length, 4, 'first try plus three retries');
});

Deno.test('an empty answer is not retried elsewhere', async () => {
  const f = fakeFetch({ 'a.test': () => reply(''), 'b.test': () => reply('from b') });
  assertEquals(await completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait), '');
  assertEquals(f.asked, ['a.test']);
});

Deno.test('when both fail, both reasons are reported', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('down', { status: 503 }),
    'b.test': () => new Response('bad key', { status: 401 }),
  });
  const err = await assertRejects(() => completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait));
  const msg = (err as Error).message;
  assertEquals(msg.includes('503 (primary)') && msg.includes('401 (fallback)'), true);
});

Deno.test('no provider at all says what to set', async () => {
  await assertRejects(() => completeWith([], { user: 'hi' }), Error, 'AI_API_KEY');
});

Deno.test('a key every provider refuses is a credentials error', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('{"error":{"code":"expired_api_key"}}', { status: 401 }),
    'b.test': () => new Response('forbidden', { status: 403 }),
  });
  const err = await assertRejects(() => completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait));
  assertEquals(err instanceof AiCredentialsError, true);
  assertEquals((err as Error).message.includes('expired_api_key'), true);
});

Deno.test('a refused key with a fallback that is merely down is not a credentials error', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('expired', { status: 401 }),
    'b.test': () => new Response('down', { status: 503 }),
  });
  const err = await assertRejects(() => completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait));
  assertEquals(err instanceof AiCredentialsError, false);
});

Deno.test('a refused primary key is covered by a working fallback', async () => {
  const f = fakeFetch({
    'a.test': () => new Response('expired', { status: 401 }),
    'b.test': () => reply('from b'),
  });
  assertEquals(await completeWith([primary, fallback], { user: 'hi' }, f.fn, noWait), 'from b');
});
