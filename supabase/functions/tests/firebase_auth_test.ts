// Firebase sign-in, server side: a token is accepted only if Google's key
// signed it for this project and it is current; a session links the account
// once and sets the claims Supabase needs; an address belonging to an existing
// account is not handed over before Firebase confirms the caller owns it.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { resetJwksCache, signForTest, verifyFirebaseToken } from '../_shared/firebase.ts';
import { startSession } from '../firebase-session/logic.ts';

const project = 'lizzy-test';
const now = 1_790_000_000;

async function keys() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  ) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return { pair, jwks: () => Promise.resolve({ keys: [{ ...jwk, kid: 'k1' }], maxAgeSeconds: 3600 }) };
}

function claims(over: Record<string, unknown> = {}) {
  return {
    iss: `https://securetoken.google.com/${project}`,
    aud: project,
    sub: 'fbUser123',
    iat: now - 60,
    auth_time: now - 60,
    exp: now + 3000,
    email: 'a@example.com',
    email_verified: true,
    ...over,
  };
}

Deno.test('a token signed for this project is accepted', async () => {
  resetJwksCache();
  const { pair, jwks } = await keys();
  const token = await signForTest(claims(), pair.privateKey, 'k1');
  const out = await verifyFirebaseToken(token, project, { fetchJwks: jwks, now });
  assertEquals(out?.sub, 'fbUser123');
});

Deno.test('wrong project, expired, future, unsigned or unknown key: refused', async () => {
  resetJwksCache();
  const { pair, jwks } = await keys();
  const other = await keys();
  const cases: [string, Promise<string>][] = [
    ['other audience', signForTest(claims({ aud: 'someone-else' }), pair.privateKey, 'k1')],
    ['other issuer', signForTest(claims({ iss: 'https://securetoken.google.com/x' }), pair.privateKey, 'k1')],
    ['expired', signForTest(claims({ exp: now - 600 }), pair.privateKey, 'k1')],
    ['issued in the future', signForTest(claims({ iat: now + 3600 }), pair.privateKey, 'k1')],
    ['no subject', signForTest(claims({ sub: '' }), pair.privateKey, 'k1')],
    ['signed by another key', signForTest(claims(), other.pair.privateKey, 'k1')],
    ['unknown key id', signForTest(claims(), pair.privateKey, 'k9')],
  ];
  for (const [name, token] of cases) {
    assertEquals(await verifyFirebaseToken(await token, project, { fetchJwks: jwks, now }), null, name);
  }
  const good = await signForTest(claims(), pair.privateKey, 'k1');
  const [h, b] = good.split('.');
  assertEquals(await verifyFirebaseToken(`${h}.${b}.`, project, { fetchJwks: jwks, now }), null, 'no signature');
  assertEquals(await verifyFirebaseToken('not.a.token', project, { fetchJwks: jwks, now }), null, 'garbage');
});

function deps(over: { link?: string | null; claims?: Record<string, unknown> | null } = {}) {
  const calls: { link: unknown[]; set: unknown[] } = { link: [], set: [] };
  return {
    calls,
    d: {
      claims: () => Promise.resolve(over.claims === null ? null : ({ sub: 'fb1', email: 'a@example.com', email_verified: true, ...over.claims } as never)),
      link: (a: unknown) => {
        calls.link.push(a);
        return Promise.resolve(over.link === undefined ? 'uuid-1' : over.link);
      },
      setClaims: (uid: string, c: Record<string, unknown>) => {
        calls.set.push([uid, c]);
        return Promise.resolve();
      },
    },
  };
}

Deno.test('no valid token, no session', async () => {
  const { d, calls } = deps({ claims: null });
  const out = await startSession(d, {});
  assertEquals(out.status, 401);
  assertEquals(calls.link.length, 0);
});

Deno.test('a first sign-in sets the claims and asks for a refresh', async () => {
  const { d, calls } = deps();
  const out = await startSession(d, { display_name: '  Ada  ' });
  assertEquals(out.body.data, { user_id: 'uuid-1', refresh: true });
  assertEquals(calls.set, [['fb1', { role: 'authenticated', liz_uid: 'uuid-1' }]]);
  assertEquals((calls.link[0] as { displayName: string }).displayName, 'Ada');
});

Deno.test('claims already in place are left alone', async () => {
  const { d, calls } = deps({ claims: { role: 'authenticated', liz_uid: 'uuid-1' } });
  const out = await startSession(d, {});
  assertEquals(out.body.data, { user_id: 'uuid-1', refresh: false });
  assertEquals(calls.set.length, 0);
});

Deno.test('an address that needs verifying gets no account and no claims', async () => {
  const { d, calls } = deps({ link: null, claims: { email_verified: false } });
  const out = await startSession(d, {});
  assertEquals(out.body.data, { needs_verification: true });
  assertEquals(calls.set.length, 0);
  assert(!(calls.link[0] as { emailVerified: boolean }).emailVerified);
});
