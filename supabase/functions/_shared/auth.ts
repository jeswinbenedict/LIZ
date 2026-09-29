// Who is allowed to start work that costs money.
//
// The ingestion functions — fetch-news, fetch-tools, embed-tools,
// summarize-tools — each build a service-role client and then scrape, embed or
// call an LLM. None of them checked its caller. Supabase's own `verify_jwt`
// does not help on its own: the anon key *is* a valid JWT, and it ships inside
// the client bundle, so "requires a JWT" and "public" are the same sentence.
//
// Measured against the live project before this existed: fetch-news answered
// 200 with no credentials at all, and the other three answered 200 to the anon
// key. Anyone could have run the catalog's scrapers and the Groq budget flat.
//
// These functions have exactly two legitimate callers, pg_cron and GitHub
// Actions, and both hold a service-role credential. So that is the bar.

import { corsHeaders, json } from './cors.ts';

/// Compares two secrets without leaking their contents through timing.
///
/// A plain `===` returns as soon as two bytes differ, so how long it takes is a
/// measurement of how much of the prefix was right — enough to reconstruct a
/// key one character at a time against a patient caller.
function constantTimeEquals(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

/// The bearer token on a request, or an empty string.
export function bearerToken(req: Request): string {
  const header = req.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1].trim() : '';
}

/// The `role` claim of a JWT, without verifying its signature.
///
/// Safe here, and ONLY here, because `verify_jwt = true` is set for every
/// function that calls this (supabase/config.toml). The platform validates the
/// signature before the request reaches this code, so by the time we read the
/// payload it is already known to have been issued by this project.
///
/// If that setting is ever turned off, this claim becomes forgeable and this
/// function stops meaning anything. The exact-key comparison below does not
/// depend on it, which is why both paths exist.
export function jwtRole(token: string): string | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    let payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    payload += '='.repeat((4 - (payload.length % 4)) % 4);
    const claims = JSON.parse(atob(payload));
    return typeof claims?.role === 'string' ? claims.role : null;
  } catch (_) {
    return null;
  }
}

/// Whether the caller presented a service-role credential.
///
/// Two accepted shapes, because this project carries both key generations:
/// the newer `sb_secret_…` keys are opaque strings, and the legacy ones are
/// JWTs whose payload names the role. Checking only one shape rejected pg_cron
/// and CI, which is how this was caught.
export function isServiceRole(req: Request): boolean {
  const presented = bearerToken(req);
  if (!presented) return false;

  // 1. The exact key this deployment was handed. Works for opaque keys, and
  //    does not rely on the platform having verified anything.
  const expected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (expected && constantTimeEquals(presented, expected)) return true;

  // 2. A platform-verified JWT that claims the service role. This is what
  //    cron and CI actually send when the project still uses legacy keys.
  return jwtRole(presented) === 'service_role';
}

/// Whether the caller presented the evaluation key (secret `ASK_EVAL_KEY`)
/// in an `x-liz-eval` header.
///
/// A separate random secret rather than the service key or a JWT role claim:
/// it is safe in a function deployed with `verify_jwt = false`, where nobody
/// has checked a claim's signature, and it grants nothing but skipping the
/// public rate limit on ask-liz so the evaluation set can run in one go.
export function presentsEvalKey(req: Request): boolean {
  const presented = req.headers.get('x-liz-eval') ?? '';
  const expected = Deno.env.get('ASK_EVAL_KEY') ?? '';
  return expected.length >= 32 && constantTimeEquals(presented, expected);
}

/// Guard for a function that only cron and CI may run.
///
/// Returns a response to send back when the caller is not allowed, or null to
/// carry on — one line at the top of a handler, impossible to half-apply.
export function requireServiceRole(req: Request): Response | null {
  if (isServiceRole(req)) return null;
  // Deliberately terse: an error that explains which half of the credential
  // was wrong is an error that helps someone guess the other half.
  return json({ data: null, error: 'Not authorized' }, 401);
}

/// Handles the CORS preflight these functions still receive.
export function preflight(req: Request): Response | null {
  if (req.method !== 'OPTIONS') return null;
  return new Response('ok', { headers: corsHeaders });
}
