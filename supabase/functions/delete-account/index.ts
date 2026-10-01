// POST /delete-account — permanently delete the caller's account.
//
// The caller is identified by their Firebase ID token, verified here
// (verify_jwt = false; see _shared/firebase.ts and migration 0055). Deleting
// the profile row removes everything tied to it through ON DELETE CASCADE —
// posts, reviews, saves, preferences, the Firebase link (see migration 0033
// for why that cascade needs definer-rights counter triggers). Then the
// sign-in itself goes: the Firebase account, and a Supabase Auth login if the
// account predates the switch.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { bearerToken } from '../_shared/auth.ts';
import { corsHeaders, json } from '../_shared/cors.ts';
import { deleteFirebaseUser, verifyFirebaseToken } from '../_shared/firebase.ts';
import { serviceAccount } from '../_shared/google.ts';
import { deleteCaller } from './logic.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const sa = serviceAccount();
    if (!sa) return json({ data: null, error: 'Firebase is not configured' }, 503);
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    let firebaseUid = '';

    const outcome = await deleteCaller({
      callerId: async () => {
        const claims = await verifyFirebaseToken(bearerToken(req), sa.project_id);
        if (!claims) return null;
        firebaseUid = claims.sub;
        const { data } = await admin
          .from('firebase_accounts')
          .select('user_id')
          .eq('firebase_uid', claims.sub)
          .maybeSingle();
        return (data?.user_id as string | undefined) ?? null;
      },
      deleteUser: async (id) => {
        const { error } = await admin.from('profiles').delete().eq('id', id);
        if (error) return error.message;
        // A login from before the switch; most accounts have none.
        const legacy = await admin.auth.admin.deleteUser(id);
        if (legacy.error && legacy.error.status !== 404) {
          console.warn('legacy auth user not deleted', legacy.error.message);
        }
        return await deleteFirebaseUser(sa, firebaseUid);
      },
    });
    return json(outcome.body, outcome.status);
  } catch (err) {
    console.error('delete-account failed', err);
    return json({ data: null, error: 'Could not delete the account' }, 500);
  }
});
