// POST /summarize-news — writes the "quick take" folded under each story on
// the News page.
//
// Body: { "limit": 6 }  (optional)
// Returns: { data: { summarized, remaining }, error }
//
// Drains the news_needing_summary view (migration 0058): recent published
// stories with a real snippet and no bullets yet. Idempotent, like
// summarize-tools, so pg_cron can call it every fifteen minutes; a story that
// yields nothing usable three times leaves the queue.
//
// Deploy: supabase functions deploy summarize-news

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { clampLimit, summarizeBatch } from '../_shared/batch.ts';
import { summarize } from '../_shared/summary.ts';

const DEFAULT_LIMIT = 6;
const MAX_LIMIT = 12;

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // Service role only: it spends model quota. See _shared/auth.ts.
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
      .from('news_needing_summary')
      .select('id,title,snippet')
      .limit(limit);

    if (selectError) return json({ data: null, error: selectError.message }, 500);
    if (!pending || pending.length === 0) {
      return json({ data: { summarized: 0, remaining: 0 }, error: null });
    }

    const { summarized, failures, credentials } = await summarizeBatch(
      pending.map((n) => ({ id: n.id, name: n.title, description: n.snippet })),
      {
        summarize: (input) => summarize({ ...input, kind: 'news' }),
        save: async (id, bullets) => {
          const { error } = await supabase
            .from('news')
            .update({ ai_summary: bullets })
            .eq('id', id);
          return error?.message ?? null;
        },
        noteAttempt: async (id) => {
          await supabase.rpc('note_news_summary_attempt', { news_id: id });
        },
      },
    );

    const { count } = await supabase
      .from('news_needing_summary')
      .select('id', { count: 'exact', head: true });

    // Same as summarize-tools: a refused key is reported, not a bad row.
    if (credentials) {
      return json({
        data: { summarized, remaining: count ?? 0 },
        error: `ai_credentials: ${credentials}`,
      }, 503);
    }

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
