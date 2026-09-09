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
import { corsHeaders, json } from '../_shared/cors.ts';

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

// ---------------------------------------------------------------------------
// Not every popular repo is a product.
//
// GitHub's topic search returns courses, awesome-lists and prompt dumps
// alongside real tools, and publishing those as "AI tools" is what answered
// "review my pull requests" with a curated link list and a terminal statusline.
// Someone browsing Liz wants something they can use, not something to read.
// ---------------------------------------------------------------------------

const NON_PRODUCT_TOPICS = new Set([
  'awesome', 'awesome-list', 'awesome-lists', 'tutorial', 'tutorials', 'course',
  'courses', 'learning', 'education', 'educational', 'book', 'books', 'ebook',
  'cheatsheet', 'roadmap', 'interview', 'interview-questions', 'papers', 'paper',
  'study', 'curriculum', 'workshop', 'examples', 'demo', 'boilerplate',
  'template', 'starter', 'list', 'collection', 'resources',
]);

// Matched against the repo name, where these words are decisive.
const NON_PRODUCT_NAME = [
  /awesome/i,
  /\b(course|courses|tutorial|tutorials|lesson|lessons)\b/i,
  /(^|[-_])(beginners?|101|basics|bootcamp|workshop|curriculum)([-_]|$)/i,
  /(^|[-_])learn([-_]|$)/i,
  /from[-_ ]scratch/i,
  /\b(roadmap|cheat[-_ ]?sheet|checklist|handbook|guide|guides|glossary)\b/i,
  /\b(leaks?|dumps?)\b/i,
  /\b(examples?|samples?|boilerplate|template|starter[-_ ]?kit)\b/i,
  // "prompt" is deliberately absent: prompt-optimizer is a real tool, while a
  // prompt *collection* is caught by the description rules instead.
  /(^|[-_])(list|lists|gallery|collection)([-_]|$)/i,
  /[-_]list$/i,
];

// Matched against the description. Kept to phrases that only ever describe
// reading material, so a real tool mentioning "examples" is not caught.
const NON_PRODUCT_DESCRIPTION = [
  /\b\d+\s+lessons?\b/i,
  /\b(a\s+)?(curated|comprehensive)\s+(list|collection|repository)\b/i,
  /\bone[-\s]stop\s+(repository|shop|resource)\b/i,
  /\b(list|collection)\s+of\s+(awesome|free|useful|the\s+best)\b/i,
  /\bcourse\s+to\s+(get|learn)\b/i,
  /\b(learn|teaches?|teaching)\s+(you\s+)?how\s+to\b/i,
  /\bstep[-\s]by[-\s]step\b/i,
  /\b(guides?|papers|notebooks|lessons|resources)\s+(and|,)\s+/i,
  /\bextracted\s+system\s+prompts\b/i,
  // "This GitHub repo is a powerhouse collection …" — allow qualifiers between
  // "this" and "repo", and adjectives before the noun.
  /\bthis\s+(\w+\s+)?repo(sitory)?\s+(is\s+a\s+|showcases|contains|provides)/i,
  /\b(powerhouse|hand[-\s]?curated|comprehensive)\s+(collection|list|resources)\b/i,
  /\bprompt\s+(gallery|library|collection)\b/i,
  /\bimplementation\s+of\s+.*\bin\s+(pytorch|tensorflow|jax)\b/i,
];

export function isNonProduct(
  name: string,
  description: string,
  topics: string[],
): boolean {
  if (topics.some((t) => NON_PRODUCT_TOPICS.has(t.toLowerCase()))) return true;
  if (NON_PRODUCT_NAME.some((re) => re.test(name))) return true;
  if (NON_PRODUCT_DESCRIPTION.some((re) => re.test(description))) return true;
  return false;
}

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
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

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
          website_url: r.homepage && r.homepage.startsWith('http') ? r.homepage : r.html_url,
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
          // trend_score is deliberately not set here. refresh_trend_scores()
          // owns it, normalising every tool onto one 0-100 scale from the
          // engagement signals below. Writing a raw log10(stars) figure here
          // overwrote that with a different scale that ran past 100, which put
          // trending repos above ChatGPT on Discover while their rank badges
          // still read #41.
          view_count: r.stargazers_count,
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
