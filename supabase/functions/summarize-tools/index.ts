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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';
import { summarize } from '../_shared/summary.ts';

const DEFAULT_LIMIT = 4;
const MAX_LIMIT = 10;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const limit = Math.min(Number(body?.limit) || DEFAULT_LIMIT, MAX_LIMIT);

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

    let summarized = 0;
    const failures: string[] = [];

    for (const tool of pending) {
      try {
        const bullets = await summarize({
          title: tool.name,
          description: `${tool.tagline ?? ''} ${tool.description ?? ''}`.trim(),
        });

        // A row that yields nothing usable will usually yield nothing usable
        // again — a README that is a badge table, a description that is one
        // line of shell. Skipping alone leaves it in the backlog forever, so
        // once this has happened three times the row drops out of the view and
        // stops spending a batch slot every quarter of an hour.
        //
        // Only this branch counts. A thrown error is a rate limit or a network
        // failure, which is not the row's fault.
        if (bullets.length === 0) {
          failures.push(`${tool.name}: no usable bullets`);
          await supabase.rpc('note_summary_attempt', { tool_id: tool.id });
          continue;
        }

        const { error: updateError } = await supabase
          .from('tools')
          .update({ ai_summary: bullets })
          .eq('id', tool.id);

        if (updateError) failures.push(`${tool.name}: ${updateError.message}`);
        else summarized++;
      } catch (err) {
        failures.push(`${tool.name}: ${String(err)}`);
      }
    }

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
