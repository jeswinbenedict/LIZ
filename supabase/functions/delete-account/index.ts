// POST /delete-account — permanently delete the caller's account (App Store /
// Play Store requirement). Uses the service role to remove the auth user;
// ON DELETE CASCADE removes their profile, posts, reviews, etc.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get('Authorization') ?? '';

    // Identify the caller from their JWT.
    const asUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData } = await asUser.auth.getUser();
    const userId = userData.user?.id;
    if (!userId) {
      return json({ data: null, error: 'Sign in required' }, 401);
    }

    // Delete with the service role (admin API).
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) return json({ data: null, error: error.message }, 400);

    return json({ data: { ok: true }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
