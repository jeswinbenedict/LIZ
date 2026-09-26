import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  bearerToken,
  isServiceRole,
  jwtRole,
  requireServiceRole,
} from '../_shared/auth.ts';

/// The ingestion functions run with the service role and spend real quota.
/// Before this guard existed, fetch-news answered 200 with no credentials and
/// the other three answered 200 to the anon key — which is public, because it
/// ships inside the client bundle.

const SECRET = 'sb_secret_opaque_key_value';
const ANON = 'anon-key-value';

// The project carries both key generations. Newer keys are opaque strings;
// legacy ones are JWTs whose payload names the role, and those are what pg_cron
// and CI actually send.
const LEGACY_SERVICE_JWT = 'eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJpc3MiOiAic3VwYWJhc2UiLCAicm9sZSI6ICJzZXJ2aWNlX3JvbGUifQ.signature';
const LEGACY_ANON_JWT = 'eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJpc3MiOiAic3VwYWJhc2UiLCAicm9sZSI6ICJhbm9uIn0.signature';

function req(authorization?: string): Request {
  return new Request('https://x.functions.supabase.co/fetch-news', {
    method: 'POST',
    headers: authorization ? { Authorization: authorization } : {},
  });
}

function withKey(key: string | undefined, run: () => void) {
  const previous = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (key === undefined) Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
  else Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', key);
  try {
    run();
  } finally {
    if (previous === undefined) Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
    else Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', previous);
  }
}

Deno.test('the service-role key is accepted', () => {
  withKey(SECRET, () => {
    assert(isServiceRole(req(`Bearer ${SECRET}`)));
    assertEquals(requireServiceRole(req(`Bearer ${SECRET}`)), null);
  });
});

Deno.test('the anon key is refused', () => {
  // The whole point. A valid JWT is not an authorization.
  withKey(SECRET, () => {
    assertEquals(isServiceRole(req(`Bearer ${ANON}`)), false);
    assertEquals(requireServiceRole(req(`Bearer ${ANON}`))?.status, 401);
  });
});

Deno.test('no credentials at all are refused', () => {
  withKey(SECRET, () => {
    assertEquals(isServiceRole(req()), false);
    assertEquals(requireServiceRole(req())?.status, 401);
  });
});

Deno.test('an empty or malformed header is refused', () => {
  withKey(SECRET, () => {
    for (const header of ['', 'Bearer', 'Bearer ', SECRET, `Basic ${SECRET}`]) {
      assertEquals(isServiceRole(req(header)), false, `header: "${header}"`);
    }
  });
});

Deno.test('a near-miss key is refused', () => {
  withKey(SECRET, () => {
    assertEquals(isServiceRole(req(`Bearer ${SECRET}x`)), false);
    assertEquals(isServiceRole(req(`Bearer ${SECRET.slice(0, -1)}`)), false);
    // Same length, one byte different — the case a constant-time compare has
    // to get right.
    const flipped = `${SECRET.slice(0, -1)}X`;
    assertEquals(isServiceRole(req(`Bearer ${flipped}`)), false);
  });
});

Deno.test('the scheme is matched case-insensitively, as HTTP requires', () => {
  withKey(SECRET, () => {
    assert(isServiceRole(req(`bearer ${SECRET}`)));
    assert(isServiceRole(req(`BEARER ${SECRET}`)));
  });
});

Deno.test('the refusal says nothing useful to a guesser', async () => {
  let response: Response | null = null;
  withKey(SECRET, () => {
    response = requireServiceRole(req(`Bearer ${ANON}`));
  });
  const body = await response!.json();
  assertEquals(body.error, 'Not authorized');
  // No hint about length, prefix, or which half was wrong.
  assertEquals(JSON.stringify(body).includes(ANON), false);
});

Deno.test('bearerToken extracts only the token', () => {
  assertEquals(bearerToken(req('Bearer abc')), 'abc');
  assertEquals(bearerToken(req('  Bearer   abc  ')), 'abc');
  assertEquals(bearerToken(req()), '');
});

Deno.test('a preflight is answered before the guard runs', () => {
  // The browser never sends credentials on an OPTIONS probe, so rejecting it
  // would break CORS for anything calling these from a page.
  const options = new Request('https://x.functions.supabase.co/fetch-news', {
    method: 'OPTIONS',
  });
  withKey(SECRET, () => {
    assertEquals(isServiceRole(options), false);
  });
  assertEquals(options.method, 'OPTIONS');
});

Deno.test('a legacy service-role JWT is accepted', () => {
  // This is the case that broke cron and CI when the check only compared the
  // token against the one key the runtime was handed.
  withKey(SECRET, () => {
    assert(isServiceRole(req(`Bearer ${LEGACY_SERVICE_JWT}`)));
  });
});

Deno.test('a legacy anon JWT is refused', () => {
  withKey(SECRET, () => {
    assertEquals(isServiceRole(req(`Bearer ${LEGACY_ANON_JWT}`)), false);
  });
});

Deno.test('the role claim is read, not guessed', () => {
  assertEquals(jwtRole(LEGACY_SERVICE_JWT), 'service_role');
  assertEquals(jwtRole(LEGACY_ANON_JWT), 'anon');
  assertEquals(jwtRole('not.a.jwt'), null);
  assertEquals(jwtRole('two.parts'), null);
  assertEquals(jwtRole(''), null);
});

Deno.test('a JWT with no role claim is refused', () => {
  const noRole = 'eyJhbGciOiJIUzI1NiJ9.' +
    btoa(JSON.stringify({ iss: 'supabase' })).replace(/=+$/, '') + '.sig';
  withKey(SECRET, () => {
    assertEquals(isServiceRole(req(`Bearer ${noRole}`)), false);
  });
});

Deno.test('a missing server key still admits a legacy service JWT', () => {
  // The two paths are independent on purpose: one survives a lost env var,
  // the other survives an opaque key that carries no claims.
  withKey(undefined, () => {
    assert(isServiceRole(req(`Bearer ${LEGACY_SERVICE_JWT}`)));
    assertEquals(isServiceRole(req(`Bearer ${LEGACY_ANON_JWT}`)), false);
    assertEquals(isServiceRole(req(`Bearer ${SECRET}`)), false);
  });
});
