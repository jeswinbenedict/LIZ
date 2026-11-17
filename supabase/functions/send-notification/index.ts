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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json, failure } from '../_shared/cors.ts';
import { accessToken, serviceAccount } from '../_shared/google.ts';
import { fcmMessage, isDeadToken, targetIds } from './logic.ts';


Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // Server-to-server only: the notify_user() trigger, with the service role.
  // This had its own copy of the role check, which skipped base64 padding and
  // did not accept the newer opaque keys; it now uses the shared, tested one.
  const denied = requireServiceRole(req);
  if (denied) return denied;

  try {
    const sa = serviceAccount();
    if (!sa) {
      // Push not configured — succeed quietly so triggers don't fail.
      return json({ data: { skipped: true, reason: 'push-not-configured' }, error: null });
    }

    const payload = await req.json();
    const { title, body, route, data = {} } = payload;
    const ids = targetIds(payload);
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
    if (error) return failure('send-notification', error, 400);

    const tokens = (devices ?? []).map((d) => d.fcm_token).filter(Boolean);
    if (tokens.length === 0) {
      return json({ data: { sent: 0, reason: 'no-devices' }, error: null });
    }

    const bearer = await accessToken(sa, 'https://www.googleapis.com/auth/firebase.messaging');
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    // FCM v1 sends one token per request. Fan out, then prune stale tokens.
    const stale: string[] = [];
    let sent = 0;
    await Promise.all(tokens.map(async (token) => {
      const message = fcmMessage(token, { title, body, route, data });
      const r = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${bearer}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(message),
      });
      if (r.ok) {
        sent++;
      } else if (isDeadToken(r.status)) {
        stale.push(token);
      }
    }));

    if (stale.length > 0) {
      await admin.from('devices').delete().in('fcm_token', stale);
    }

    return json({ data: { sent, pruned: stale.length }, error: null });
  } catch (err) {
    return failure('send-notification', err, 500);
  }
});
