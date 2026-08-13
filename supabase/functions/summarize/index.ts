// POST /summarize — generate a 3-bullet AI summary for a tool or article.
//
// Called by n8n at ingest time and available to the admin panel. Body:
//   { "title": "...", "description": "...", "kind": "tool" | "news" }
// Returns: { data: { bullets: string[] }, error }

import { corsHeaders, json } from '../_shared/cors.ts';
import { completeText, extractJson } from '../_shared/ai.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const { title, description, kind = 'tool' } = await req.json();
    if (!title && !description) {
      return json({ data: null, error: 'Provide title or description' }, 400);
    }

    const system =
      'You write crisp, factual 3-bullet summaries of AI tools and tech news for a ' +
      'discovery app. Each bullet is one short sentence, benefit-focused, no hype. ' +
      'Respond ONLY with JSON: {"bullets": ["...","...","..."]}.';

    const text = await completeText({
      system,
      maxTokens: 400,
      user: `Kind: ${kind}\nTitle: ${title ?? ''}\nDescription: ${description ?? ''}`,
    });

    const parsed = extractJson<{ bullets: string[] }>(text, { bullets: [] });
    const bullets = (parsed.bullets ?? []).slice(0, 3);
    return json({ data: { bullets }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
