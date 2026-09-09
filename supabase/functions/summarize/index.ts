// POST /summarize — generate a 3-bullet AI summary for a tool or article.
//
// Called by n8n at ingest time and available to the admin panel. Body:
//   { "title": "...", "description": "...", "kind": "tool" | "news" }
// Returns: { data: { bullets: string[] }, error }

import { corsHeaders, json } from '../_shared/cors.ts';
import { summarize } from '../_shared/summary.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const { title, description, kind = 'tool' } = await req.json();
    if (!title && !description) {
      return json({ data: null, error: 'Provide title or description' }, 400);
    }

    const bullets = await summarize({ title, description, kind });

    return json({ data: { bullets }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
