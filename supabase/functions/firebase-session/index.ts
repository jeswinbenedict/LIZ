// POST /firebase-session — called by the app after every Firebase sign-in.
//
// Body: { display_name? }   Auth: the caller's Firebase ID token as bearer.
// Returns { user_id, refresh } — refresh the ID token when refresh is true —
// or { needs_verification: true } when the email address belongs to an
// existing Liz account and Firebase has not yet confirmed the caller owns it.
//
// Deployed with verify_jwt = false: the token is Firebase's, and it is
// verified here (see _shared/firebase.ts). See migration 0055.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { bearerToken, preflight } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { setCustomClaims, verifyFirebaseToken } from '../_shared/firebase.ts';
import { serviceAccount } from '../_shared/google.ts';
import { startSession } from './logic.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const sa = serviceAccount();
  if (!sa) return json({ data: null, error: 'Firebase is not configured' }, 503);

  try {
    const body = await req.json().catch(() => ({}));
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const outcome = await startSession({
      claims: () => verifyFirebaseToken(bearerToken(req), sa.project_id),
      link: async (a) => {
        const { data, error } = await admin.rpc('link_firebase_account', {
          p_firebase_uid: a.firebaseUid,
          p_email: a.email,
          p_email_verified: a.emailVerified,
          p_display_name: a.displayName,
          p_avatar_url: a.avatarUrl,
        });
        if (error) throw new Error(error.message);
        return (data as string | null) ?? null;
      },
      setClaims: (uid, claims) => setCustomClaims(sa, uid, claims),
    }, body ?? {});
    return json(outcome.body, outcome.status);
  } catch (err) {
    console.error('firebase-session failed', err);
    return json({ data: null, error: 'Could not start the session' }, 500);
  }
});
