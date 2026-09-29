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
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { clampLimit, embedBatch } from '../_shared/batch.ts';
import { EMBEDDING_MODEL, EMBEDDING_VERSION, embed, toolText } from '../_shared/embed.ts';

const DEFAULT_LIMIT = 5;
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
      // service role: writing embeddings bypasses RLS, so keep this server-side
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: pending, error: selectError } = await supabase
      .from('tools_needing_embedding')
      .select('id,name,tagline,description,category,tags,ai_summary')
      .limit(limit);

    if (selectError) {
      return json({ data: null, error: selectError.message }, 500);
    }
    if (!pending || pending.length === 0) {
      return json({ data: { embedded: 0, remaining: 0, model: EMBEDDING_MODEL }, error: null });
    }

    const { embedded, failures } = await embedBatch(pending, {
      text: toolText,
      embed,
      save: async (id, vector) => {
        const { error } = await supabase
          .from('tools')
          .update({
            embedding: vector,
            embedding_model: EMBEDDING_VERSION,
            embedded_at: new Date().toISOString(),
          })
          .eq('id', id);
        return error?.message ?? null;
      },
    });

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
