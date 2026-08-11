// POST /report — record a content report and apply the auto-hide threshold.
//
// The DB trigger (handle_report) already auto-hides at the threshold, but this
// function lets the client report via an authenticated call and returns a
// friendly acknowledgement. Body:
//   { "target_type": "post"|"comment"|"review"|"tool", "target_id": "...", "reason": "..." }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    // Use the caller's JWT so RLS attributes the report to the right user.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData.user?.id;
    if (!userId) {
      return json({ data: null, error: 'Sign in required' }, 401);
    }

    const { target_type, target_id, reason } = await req.json();
    const valid = ['post', 'comment', 'review', 'tool'];
    if (!valid.includes(target_type) || !target_id) {
      return json({ data: null, error: 'Invalid report target' }, 400);
    }

    const { error } = await supabase.from('reports').insert({
      reporter_id: userId,
      target_type,
      target_id,
      reason: (reason ?? '').toString().slice(0, 500),
    });
    if (error) return json({ data: null, error: error.message }, 400);

    return json({ data: { ok: true }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
