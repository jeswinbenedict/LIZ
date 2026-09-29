// POST /fetch-tools — ingest trending AI projects from GitHub into `tools`.
//
// Free, no key required (GitHub's unauthenticated search allows ~10 req/min,
// plenty for a daily cron). Each repo brings a REAL logo via owner.avatar_url.
// Normalizes, categorizes from topics, dedupes by content_hash, and upserts
// with status='published' so items appear live in Discover.
//
// Auth: call with any valid project JWT (anon or service role). The daily cron
// uses the service role from Vault.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { isNonProduct, websiteFor } from './logic.ts';

// Search buckets → each maps to a Liz category. Kept product-focused.
const QUERIES: { q: string; category: string }[] = [
  { q: 'topic:ai-tools stars:>800', category: 'ai-dev' },
  { q: 'topic:llm stars:>1500', category: 'ai-dev' },
  { q: 'topic:generative-ai stars:>1200', category: 'ai-image' },
  { q: 'topic:ai-agent stars:>800', category: 'ai-agents' },
  { q: 'topic:text-to-image stars:>1000', category: 'ai-image' },
  { q: 'topic:text-to-speech stars:>800', category: 'ai-audio' },
];

const TOPIC_CATEGORY: Record<string, string> = {
  'image': 'ai-image', 'text-to-image': 'ai-image', 'stable-diffusion': 'ai-image',
  'video': 'ai-video', 'text-to-video': 'ai-video',
  'tts': 'ai-audio', 'text-to-speech': 'ai-audio', 'speech': 'ai-audio', 'music': 'ai-audio',
  'agent': 'ai-agents', 'ai-agent': 'ai-agents', 'agents': 'ai-agents', 'autonomous': 'ai-agents',
  'writing': 'ai-writing', 'nlp': 'ai-writing',
  'design': 'ai-design', 'ui': 'ai-design',
  'productivity': 'ai-productivity',
  'research': 'ai-research', 'paper': 'ai-research', 'llm': 'ai-research',
};

function slugify(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60);
}

function categoryFor(topics: string[], fallback: string): string {
  for (const t of topics) if (TOPIC_CATEGORY[t]) return TOPIC_CATEGORY[t];
  return fallback;
}

interface Repo {
  id: number;
  name: string;
  full_name: string;
  description: string | null;
  html_url: string;
  homepage: string | null;
  stargazers_count: number;
  topics: string[];
  pushed_at: string;
  owner: { login: string; avatar_url: string };
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // Only cron and CI may start this: it runs with the service role and spends
  // real quota. See _shared/auth.ts.
  const denied = requireServiceRole(req);
  if (denied) return denied;

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const seen = new Set<string>();
    const rows: Record<string, unknown>[] = [];
    let skipped = 0;

    for (const { q, category } of QUERIES) {
      const url =
        `https://api.github.com/search/repositories?q=${encodeURIComponent(q)}` +
        `&sort=stars&order=desc&per_page=20`;
      let repos: Repo[] = [];
      try {
        const res = await fetch(url, {
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'liz-fetch-tools',
          },
        });
        if (!res.ok) continue;
        const data = await res.json();
        repos = data.items ?? [];
      } catch (_) {
        continue; // skip this bucket on error
      }

      for (const r of repos) {
        const hash = `github:${r.id}`;
        if (seen.has(hash)) continue;
        seen.add(hash);
        // Keep it product-y: needs a description; a homepage is a strong signal.
        if (!r.description) continue;

        const topics = r.topics ?? [];
        if (isNonProduct(r.name, r.description, topics)) {
          skipped++;
          continue;
        }
        rows.push({
          name: r.name,
          slug: slugify(r.full_name.replace('/', '-')),
          tagline: r.description.slice(0, 140),
          description: r.description,
          ai_summary: [],
          website_url: websiteFor(r.homepage, r.html_url),
          logo_url: r.owner.avatar_url, // real org/user logo
          category: categoryFor(topics, category),
          tags: topics.slice(0, 5),
          platforms: ['web'],
          pricing_type: 'free', // open-source
          price_note: 'Open source',
          source: 'github',
          source_url: r.html_url,
          content_hash: hash,
          launched_at: (r.pushed_at ?? new Date().toISOString()).slice(0, 10),
          // trend_score is deliberately not set here: refresh_trend_scores()
          // owns it, from growth in the daily snapshots. Stars go in their own
          // column. They used to be written into view_count, which made a star
          // count read as page views on Liz (migration 0037).
          gh_repo: r.full_name,
          gh_stars: r.stargazers_count,
          signals_at: new Date().toISOString(),
          status: 'published',
          updated_at: new Date().toISOString(),
        });
      }
    }

    if (rows.length === 0) {
      return json({ data: { ingested: 0, skipped, reason: 'no-results' }, error: null });
    }

    // Upsert by content_hash so re-runs refresh instead of duplicating.
    const { error } = await admin
      .from('tools')
      .upsert(rows, { onConflict: 'content_hash', ignoreDuplicates: false });
    if (error) return json({ data: null, error: error.message }, 400);

    return json({ data: { ingested: rows.length, skipped }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
