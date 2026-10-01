// POST /summarize-tools — fills in the AI summary bullets a tool page shows.
//
// Body: { "limit": 4 }  (optional)
// Returns: { data: { summarized, remaining, model }, error }
//
// Tools arriving from GitHub or the scraper have no ai_summary, so their detail
// page renders an empty "AI summary" section. This drains the
// tools_needing_summary view, and is idempotent: it only touches rows that
// still have no bullets, so it is safe on a schedule after every ingest.
//
// Batches are small because each row costs an LLM round trip; callers repeat
// while `remaining` is above zero.
//
// Deploy: supabase functions deploy summarize-tools

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { clampLimit, summarizeBatch } from '../_shared/batch.ts';
import { summarize } from '../_shared/summary.ts';

const DEFAULT_LIMIT = 4;
const MAX_LIMIT = 10;

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // Only cron and CI may start this: it runs with the service role and spends
  // real quota. See _shared/auth.ts.
  const denied = requireServiceRole(req);
  if (denied) return denied;

  try {
    const body = await req.json().catch(() => ({}));
    const limit = clampLimit(body, DEFAULT_LIMIT, MAX_LIMIT);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: pending, error: selectError } = await supabase
      .from('tools_needing_summary')
      .select('id,name,tagline,description')
      .limit(limit);

    if (selectError) return json({ data: null, error: selectError.message }, 500);
    if (!pending || pending.length === 0) {
      return json({ data: { summarized: 0, remaining: 0 }, error: null });
    }

    // Which failures count against a row is decided in _shared/batch.ts.
    const { summarized, failures } = await summarizeBatch(pending, {
      summarize,
      save: async (id, bullets) => {
        const { error } = await supabase
          .from('tools')
          .update({ ai_summary: bullets })
          .eq('id', id);
        return error?.message ?? null;
      },
      noteAttempt: async (id) => {
        await supabase.rpc('note_summary_attempt', { tool_id: id });
      },
    });

    const { count } = await supabase
      .from('tools_needing_summary')
      .select('id', { count: 'exact', head: true });

    return json({
      data: {
        summarized,
        remaining: count ?? 0,
        ...(failures.length ? { failures: failures.slice(0, 3) } : {}),
      },
      error: null,
    });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
