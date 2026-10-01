// Firebase Authentication, from the server's side.
//
// Liz signs people in with Firebase and keeps their data in this project
// (migration 0055). Functions that act for a signed-in person verify the
// Firebase ID token themselves rather than leaning on the gateway's
// verify_jwt, which was built for Supabase's own tokens. The checks are the
// ones Firebase documents for verifying ID tokens without its Admin SDK:
// RS256, a key Google currently publishes, issuer and audience naming this
// project, unexpired, issued and authenticated in the past, a non-empty
// subject.

import { accessToken, b64url, type ServiceAccount } from './google.ts';

export const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/// The claims Liz reads from a verified token.
export interface FirebaseClaims {
  sub: string;
  email?: string;
  email_verified?: boolean;
  name?: string;
  picture?: string;
  role?: string;
  liz_uid?: string;
  [key: string]: unknown;
}

interface Jwk extends JsonWebKey {
  kid: string;
}

type FetchJwks = () => Promise<{ keys: Jwk[]; maxAgeSeconds: number }>;

let cached: { keys: Jwk[]; until: number } | null = null;

const fetchGoogleJwks: FetchJwks = async () => {
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new Error(`JWKS ${res.status}`);
  const body = await res.json();
  const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '');
  return { keys: body.keys ?? [], maxAgeSeconds: maxAge ? Number(maxAge[1]) : 3600 };
};

async function keyFor(kid: string, fetchJwks: FetchJwks, now: number): Promise<Jwk | null> {
  if (!cached || cached.until <= now || !cached.keys.some((k) => k.kid === kid)) {
    const { keys, maxAgeSeconds } = await fetchJwks();
    cached = { keys, until: now + maxAgeSeconds };
  }
  return cached.keys.find((k) => k.kid === kid) ?? null;
}

/// Forgets cached signing keys. For tests.
export function resetJwksCache() {
  cached = null;
}

function decodePart(part: string): Record<string, unknown> {
  let s = part.replace(/-/g, '+').replace(/_/g, '/');
  s += '='.repeat((4 - (s.length % 4)) % 4);
  return JSON.parse(atob(s));
}

function decodeBytes(part: string): Uint8Array<ArrayBuffer> {
  let s = part.replace(/-/g, '+').replace(/_/g, '/');
  s += '='.repeat((4 - (s.length % 4)) % 4);
  const raw = atob(s);
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/// The verified claims of a Firebase ID token for [projectId], or null for
/// anything that is not one — expired, forged, for another project, garbled.
export async function verifyFirebaseToken(
  token: string,
  projectId: string,
  options: { fetchJwks?: FetchJwks; now?: number } = {},
): Promise<FirebaseClaims | null> {
  const now = options.now ?? Math.floor(Date.now() / 1000);
  const skew = 300;
  const parts = token.split('.');
  if (parts.length !== 3 || !projectId) return null;
  try {
    const header = decodePart(parts[0]);
    const claims = decodePart(parts[1]) as FirebaseClaims & Record<string, number | string>;
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;
    if (claims.iss !== `https://securetoken.google.com/${projectId}`) return null;
    if (claims.aud !== projectId) return null;
    if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128) return null;
    if (typeof claims.exp !== 'number' || claims.exp <= now - skew) return null;
    if (typeof claims.iat !== 'number' || claims.iat > now + skew) return null;
    if (typeof claims.auth_time === 'number' && claims.auth_time > now + skew) return null;

    const jwk = await keyFor(header.kid, options.fetchJwks ?? fetchGoogleJwks, now);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const ok = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      decodeBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    return ok ? claims : null;
  } catch (_) {
    return null;
  }
}

const ACCOUNTS = 'https://identitytoolkit.googleapis.com/v1/projects';
const SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

/// Replaces the account's custom claims. They appear in its ID tokens from
/// the next refresh.
export async function setCustomClaims(
  sa: ServiceAccount,
  uid: string,
  claims: Record<string, unknown>,
): Promise<void> {
  const res = await fetch(`${ACCOUNTS}/${sa.project_id}/accounts:update`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await accessToken(sa, SCOPE)}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ localId: uid, customAttributes: JSON.stringify(claims) }),
  });
  if (!res.ok) throw new Error(`setting claims failed: ${res.status} ${await res.text()}`);
}

/// Deletes the Firebase account. An account already gone counts as deleted.
export async function deleteFirebaseUser(sa: ServiceAccount, uid: string): Promise<string | null> {
  const res = await fetch(`${ACCOUNTS}/${sa.project_id}/accounts:delete`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await accessToken(sa, SCOPE)}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ localId: uid }),
  });
  if (res.ok) return null;
  const text = await res.text();
  return text.includes('USER_NOT_FOUND') ? null : `Firebase: ${res.status} ${text}`;
}

/// For tests: signs a token with a generated key, as Firebase would.
export async function signForTest(
  claims: Record<string, unknown>,
  privateKey: CryptoKey,
  kid: string,
): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' }));
  const body = b64url(JSON.stringify(claims));
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(`${header}.${body}`)),
  );
  return `${header}.${body}.${b64url(sig)}`;
}
