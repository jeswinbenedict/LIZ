// POST /delete-account — permanently delete the caller's account. Uses the
// service role to remove the auth user; ON DELETE CASCADE removes their
// profile, posts, reviews, bookmarks and the rest (see migration 0033 for why
// that cascade needs definer-rights counter triggers).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';
import { deleteCaller } from './logic.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const url = Deno.env.get('SUPABASE_URL')!;

    const outcome = await deleteCaller({
      // Identify the caller from their own JWT.
      callerId: async () => {
        const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data } = await asUser.auth.getUser();
        return data.user?.id ?? null;
      },
      deleteUser: async (id) => {
        const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
        const { error } = await admin.auth.admin.deleteUser(id);
        return error?.message ?? null;
      },
    });
    return json(outcome.body, outcome.status);
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
