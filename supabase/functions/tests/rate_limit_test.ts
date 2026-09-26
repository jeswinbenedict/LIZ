import { assert, assertEquals } from 'jsr:@std/assert@1';
import { callerKey, InMemoryLimiter, tooManyRequests } from '../_shared/rate_limit.ts';

/// ask-liz and logo stay anonymous on purpose, so the budget is what keeps
/// "no account needed" from also meaning "no ceiling".

function req(forwardedFor?: string): Request {
  return new Request('https://x.functions.supabase.co/logo', {
    headers: forwardedFor ? { 'x-forwarded-for': forwardedFor } : {},
  });
}

Deno.test('the caller is taken from the first forwarded address', () => {
  // x-forwarded-for is client, then each proxy it passed through.
  assertEquals(callerKey(req('203.0.113.7, 10.0.0.1'), 'logo'), 'logo:203.0.113.7');
  assertEquals(callerKey(req('  203.0.113.7  '), 'ask'), 'ask:203.0.113.7');
});

Deno.test('a request with no address still gets a bucket', () => {
  // Better to pool the unattributable together than to let them through
  // uncounted.
  assertEquals(callerKey(req(), 'logo'), 'logo:unknown');
  assertEquals(callerKey(req(''), 'logo'), 'logo:unknown');
});

Deno.test('the prefix keeps the two functions from sharing a budget', () => {
  assert(callerKey(req('1.2.3.4'), 'logo') !== callerKey(req('1.2.3.4'), 'ask-liz'));
});

Deno.test('requests are allowed up to the limit and refused after', () => {
  const limiter = new InMemoryLimiter(3, 60_000);
  assert(limiter.take('a'));
  assert(limiter.take('a'));
  assert(limiter.take('a'));
  assertEquals(limiter.take('a'), false);
  assertEquals(limiter.take('a'), false);
});

Deno.test('one caller running hot does not spend another caller budget', () => {
  const limiter = new InMemoryLimiter(2, 60_000);
  assert(limiter.take('a'));
  assert(limiter.take('a'));
  assertEquals(limiter.take('a'), false);
  // b has not asked for anything yet.
  assert(limiter.take('b'));
});

Deno.test('the budget refills when the window rolls over', () => {
  const limiter = new InMemoryLimiter(1, 20);
  assert(limiter.take('a'));
  assertEquals(limiter.take('a'), false);

  const start = Date.now();
  while (Date.now() - start < 25) {
    // Busy-wait: shorter than any sleep this would otherwise need, and the
    // window is deliberately tiny.
  }

  assert(limiter.take('a'), 'a new window should start with a full budget');
});

Deno.test('a refusal tells the caller when to come back', async () => {
  const response = tooManyRequests(600);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get('Retry-After'), '600');
  const body = await response.json();
  assertEquals(body.error, 'Too many requests');
});

Deno.test('a refusal still carries CORS, so the page can read it', () => {
  // Without this the browser reports a network error and the app cannot tell
  // "you are over the limit" from "the internet broke".
  assertEquals(
    tooManyRequests(60).headers.get('Access-Control-Allow-Origin'),
    '*',
  );
});
