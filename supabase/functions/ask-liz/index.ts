// POST /ask-liz  — natural-language tool finder.
//
// Body: { "query": "free AI tool to remove image backgrounds", "limit": 5 }
// Returns: { data: [{ tool_id, name, reason }], error }
//
// Retrieves candidate tools from the DB (broad search), asks the LLM to rank
// and explain the best fits, and returns tool cards with a "why this fits" line.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, json } from '../_shared/cors.ts';
import { completeText, extractJson } from '../_shared/anthropic.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const { query, limit = 5 } = await req.json();
    if (!query || typeof query !== 'string') {
      return json({ data: null, error: 'Missing query' }, 400);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      // service role: server-side only, never exposed to the client
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Broad candidate retrieval — the LLM does the fine ranking.
    const words = query.toLowerCase().split(/\s+/).filter((w: string) => w.length > 2);
    const orFilter = words
      .slice(0, 6)
      .map((w: string) => `name.ilike.%${w}%,tagline.ilike.%${w}%,description.ilike.%${w}%`)
      .join(',');

    let { data: candidates } = await supabase
      .from('tools')
      .select('id,name,tagline,description,pricing_type,tags,category,trend_score')
      .eq('status', 'published')
      .or(orFilter || 'name.ilike.%%')
      .limit(25);

    if (!candidates || candidates.length < 3) {
      const { data: top } = await supabase
        .from('tools')
        .select('id,name,tagline,description,pricing_type,tags,category,trend_score')
        .eq('status', 'published')
        .order('trend_score', { ascending: false })
        .limit(40);
      candidates = top ?? [];
    }

    if (candidates.length === 0) {
      return json({ data: [], error: null });
    }

    const catalog = candidates
      .map(
        (t: Record<string, unknown>) =>
          `- id:${t.id} | ${t.name} | ${t.pricing_type} | ${t.tagline} | tags:${(t.tags as string[]).join(',')}`,
      )
      .join('\n');

    const system =
      'You are Liz, an AI tool finder. Given a user need and a catalog of tools, ' +
      'pick the best matches and give a one-line reason for each. ' +
      'Only choose from the catalog. Respond ONLY with JSON: ' +
      'an array of {"tool_id": string, "reason": string}, best first.';

    const text = await completeText({
      system,
      maxTokens: 700,
      user: `User need: "${query}"\n\nCatalog:\n${catalog}\n\nReturn up to ${limit} picks as JSON.`,
    });

    type Pick = { tool_id: string; reason: string };
    const picks = extractJson<Pick[]>(text, []);
    const byId = new Map(candidates.map((t: Record<string, unknown>) => [t.id, t]));
    const results = picks
      .filter((p) => byId.has(p.tool_id))
      .slice(0, limit)
      .map((p) => ({
        tool_id: p.tool_id,
        name: (byId.get(p.tool_id) as Record<string, unknown>).name,
        reason: p.reason,
      }));

    return json({ data: results, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
