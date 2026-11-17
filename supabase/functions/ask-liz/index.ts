// POST /ask-liz — natural-language tool finder.
//
// Body: { "query": "free AI tool to remove image backgrounds", "limit": 5 }
// Returns: { data: [{ tool_id, name, reason, similarity }], error }
//
// Embeds the question with the same open-source model used for the catalog and
// returns the nearest tools by cosine similarity, so a request phrased in the
// user's own words matches a tool that never uses those words.
//
// The previous version retrieved by ILIKE over name/tagline/description and let
// an LLM rank the result. That needed an API key to work at all, and when the
// key was absent the client silently fell back to on-device keyword ranking —
// which answered "remove image backgrounds" with a Claude Code helper and a RAG
// pipeline builder, because both happened to be free and trending.
//
// Deploy: supabase functions deploy ask-liz

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { corsHeaders, json, failure } from '../_shared/cors.ts';
import { presentsEvalKey } from '../_shared/auth.ts';
import { signedInUid } from '../_shared/signed_in.ts';
import { callerKey, tooManyRequests, withinRateLimit } from '../_shared/rate_limit.ts';
import { embed } from '../_shared/embed.ts';
import { MIN_SIMILARITY, type Match, reasonFor } from './logic.ts';

const ASK_LIMIT_PER_HOUR = 30;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { query, limit = 5 } = await req.json();
    if (!query || typeof query !== 'string' || !query.trim()) {
      return json({ data: null, error: 'Missing query' }, 400);
    }

    // Signed-in people only: the answers are the catalog, which is private
    // since migration 0061. The evaluation run presents its own key instead.
    const evaluating = presentsEvalKey(req);
    if (!evaluating && !(await signedInUid(req))) {
      return json({ data: null, error: 'Sign in to ask Liz' }, 401);
    }

    // Every call runs an embedding model, so it cannot be unlimited. Thirty
    // an hour is far above what a person browsing will ever reach. The
    // evaluation run is exempt, so the question set
    // (scrapers/eval/ask_liz_questions.json) can run in one go.
    if (
      !evaluating &&
      !(await withinRateLimit(callerKey(req, 'ask-liz'), ASK_LIMIT_PER_HOUR))
    ) {
      return tooManyRequests(600);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      // service role: server-side only, never exposed to the client
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const queryEmbedding = await embed(query);

    // Meaning alone decides. A keyword match was tried as a second opinion
    // for close calls just under the floor (September 2026) and made answers
    // worse: common words like "post" and "play" admitted wrong tools to
    // questions whose honest answer is none. See scrapers/eval.
    const { data: matches, error } = await supabase.rpc('match_tools', {
      query_embedding: queryEmbedding,
      match_count: Math.min(Number(limit) || 5, 20),
      min_similarity: MIN_SIMILARITY,
    });

    if (error) {
      return failure('ask-liz', error, 500);
    }

    // No result above the floor is a legitimate answer: the client shows its
    // "no great match" state rather than padding the list with near-misses.
    const results = (matches ?? []).map((m: Match) => ({
      tool_id: m.id,
      name: m.name,
      reason: reasonFor(m, query),
      similarity: Number(m.similarity.toFixed(3)),
    }));

    return json({ data: results, error: null });
  } catch (err) {
    return failure('ask-liz', err, 500);
  }
});
