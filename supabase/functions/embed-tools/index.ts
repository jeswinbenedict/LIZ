// POST /embed-tools — backfills tool embeddings so semantic search can find them.
//
// Body: { "limit": 100 }  (optional)
// Returns: { data: { embedded, remaining, model }, error }
//
// Idempotent: only touches rows the `tools_needing_embedding` view reports as
// missing or embedded by an older model, so it is safe to run on a schedule
// after every ingestion pass.
//
// Batches are deliberately tiny. Running the model is expensive enough that an
// edge worker dies with WORKER_RESOURCE_LIMIT part way through a larger batch —
// measured against this project, 5 succeeds and 20 does not, and a failed
// invocation embeds nothing. Callers repeat while `remaining` is above zero.
//
// Deploy: supabase functions deploy embed-tools

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';
import { EMBEDDING_MODEL, embed, toolText } from '../_shared/embed.ts';

const DEFAULT_LIMIT = 5;
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
      // service role: writing embeddings bypasses RLS, so keep this server-side
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: pending, error: selectError } = await supabase
      .from('tools_needing_embedding')
      .select('id,name,tagline,description,category,tags')
      .limit(limit);

    if (selectError) {
      return json({ data: null, error: selectError.message }, 500);
    }
    if (!pending || pending.length === 0) {
      return json({ data: { embedded: 0, remaining: 0, model: EMBEDDING_MODEL }, error: null });
    }

    let embedded = 0;
    const failures: string[] = [];

    for (const tool of pending) {
      const text = toolText(tool);
      if (!text) continue;

      try {
        const vector = await embed(text);
        const { error: updateError } = await supabase
          .from('tools')
          .update({
            embedding: vector,
            embedding_model: EMBEDDING_MODEL,
            embedded_at: new Date().toISOString(),
          })
          .eq('id', tool.id);

        if (updateError) failures.push(`${tool.id}: ${updateError.message}`);
        else embedded++;
      } catch (err) {
        failures.push(`${tool.id}: ${String(err)}`);
      }
    }

    // Report what is still outstanding so a scheduler knows to run again.
    const { count } = await supabase
      .from('tools_needing_embedding')
      .select('id', { count: 'exact', head: true });

    return json({
      data: {
        embedded,
        remaining: count ?? 0,
        model: EMBEDDING_MODEL,
        ...(failures.length ? { failures: failures.slice(0, 5) } : {}),
      },
      error: null,
    });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
