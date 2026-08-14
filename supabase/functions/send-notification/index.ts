// POST /send-notification — deliver an FCM push to a user's devices.
//
// Body: { user_id | user_ids: [...], title, body, route?, data? }
// Auth: call with the SERVICE ROLE bearer (server-to-server only; the DB
//       notify_user() trigger does this via pg_net). Never expose to clients.
//
// Requires two secrets:
//   FIREBASE_SERVICE_ACCOUNT  — the full service-account JSON (one line)
//   (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected by the platform)
//
// If FIREBASE_SERVICE_ACCOUNT is absent the function returns a clean 200 with
// skipped:true, so callers/triggers never error just because push isn't set up.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

// --- Google OAuth2: sign a JWT with the SA key, exchange for an access token.
let cachedToken: { token: string; exp: number } | null = null;

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

function b64url(bytes: Uint8Array | string): string {
  const str = typeof bytes === 'string'
    ? bytes
    : String.fromCharCode(...bytes);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.token;

  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const signingInput = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
      new TextEncoder().encode(signingInput)),
  );
  const jwt = `${signingInput}.${b64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const tok = await res.json();
  if (!tok.access_token) throw new Error(`OAuth failed: ${JSON.stringify(tok)}`);
  cachedToken = { token: tok.access_token, exp: now + 3600 };
  return tok.access_token;
}

/// The gateway already verified the JWT's signature; we only read the role
/// claim to ensure the caller is server-side (the DB trigger), not a client.
function callerRole(req: Request): string | null {
  const m = (req.headers.get('Authorization') ?? '').match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const parts = m[1].split('.');
  if (parts.length < 2) return null;
  try {
    const json = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json).role ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Server-to-server only: reject anon/authenticated clients.
  if (callerRole(req) !== 'service_role') {
    return json({ data: null, error: 'forbidden' }, 403);
  }

  try {
    const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!raw) {
      // Push not configured — succeed quietly so triggers don't fail.
      return json({ data: { skipped: true, reason: 'push-not-configured' }, error: null });
    }
    const sa = JSON.parse(raw) as ServiceAccount;

    const {
      user_id,
      user_ids,
      title,
      body,
      route,
      data = {},
    } = await req.json();

    const ids: string[] = user_ids ?? (user_id ? [user_id] : []);
    if (ids.length === 0 || !title) {
      return json({ data: null, error: 'user_id(s) and title required' }, 400);
    }

    // Service-role client to read tokens + prune dead ones (bypasses RLS).
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: devices, error } = await admin
      .from('devices')
      .select('fcm_token')
      .in('user_id', ids);
    if (error) return json({ data: null, error: error.message }, 400);

    const tokens = (devices ?? []).map((d) => d.fcm_token).filter(Boolean);
    if (tokens.length === 0) {
      return json({ data: { sent: 0, reason: 'no-devices' }, error: null });
    }

    const accessToken = await getAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    // FCM v1 sends one token per request. Fan out, then prune stale tokens.
    const stale: string[] = [];
    let sent = 0;
    await Promise.all(tokens.map(async (token) => {
      const message = {
        message: {
          token,
          notification: { title: String(title), body: String(body ?? '') },
          data: Object.fromEntries(
            Object.entries({ route: route ?? '', ...data })
              .map(([k, v]) => [k, String(v)]),
          ),
          webpush: route ? { fcm_options: { link: String(route) } } : undefined,
        },
      };
      const r = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(message),
      });
      if (r.ok) {
        sent++;
      } else if (r.status === 404 || r.status === 400) {
        // UNREGISTERED / invalid token — drop it so we stop trying.
        stale.push(token);
      }
    }));

    if (stale.length > 0) {
      await admin.from('devices').delete().in('fcm_token', stale);
    }

    return json({ data: { sent, pruned: stale.length }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
