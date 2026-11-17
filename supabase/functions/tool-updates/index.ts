// POST /tool-updates — live "what's new" for a specific tool: real product
// updates, changes, and new features (NOT general press).
//
// Sources (free, no key, real-time):
//   • GitHub Releases — real changelog/version notes for tools with a public
//     repo (derived from the tool's source_url, or a small curated map).
//   • Fallback for closed tools: Google News RSS filtered to feature/update
//     announcements ("launches", "introduces", "new feature", "rolling out").
//
// Body: { name, source_url?, slug? }
// -> { data: [{title, note, url, source, published_at}], error }

import { corsHeaders, json, failure } from '../_shared/cors.ts';
import { callerKey, InMemoryLimiter, tooManyRequests } from '../_shared/rate_limit.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import {
  aboutTool,
  cacheKey,
  cacheUse,
  hackerNewsFrom,
  type Item,
  newestFirst,
  newsFrom,
  releasesFrom,
  repoFrom,
} from './logic.ts';

async function githubReleases(owner: string, repo: string): Promise<Item[]> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/releases?per_page=8`,
    { headers: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'liz-tool-updates' } },
  );
  if (!res.ok) return [];
  return releasesFrom(await res.json());
}

/**
 * Feature announcements from Google News, and what the source answered.
 *
 * The status is returned alongside because an empty list alone cannot tell
 * "nothing was announced" from "the source turned us away" — and from here it
 * came back empty for every tool while the same request worked from a home
 * connection.
 */
async function featureNews(name: string): Promise<{ items: Item[]; source: string }> {
  const q = `"${name}" (update OR "new feature" OR launches OR introduces OR "rolling out" OR announces) when:90d`;
  const res = await fetch(
    `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=en-US&gl=US&ceid=US:en`,
    { headers: { 'User-Agent': 'Mozilla/5.0 (Liz)' } },
  );
  const host = new URL(res.url).hostname;
  if (!res.ok) return { items: [], source: `google-news http ${res.status}` };
  if (host !== 'news.google.com') return { items: [], source: `google-news redirected to ${host}` };
  const body = await res.text();
  const items = newsFrom(body);
  return { items, source: `google-news ok, ${items.length} items, ${body.length} bytes` };
}

/** Hacker News stories naming the tool in the last 90 days, with traction. */
async function hackerNews(name: string): Promise<{ items: Item[]; source: string }> {
  const since = Math.floor(Date.now() / 1000) - 90 * 86400;
  const res = await fetch(
    `https://hn.algolia.com/api/v1/search_by_date?query=${encodeURIComponent(name)}` +
      `&tags=story&restrictSearchableAttributes=title` +
      `&numericFilters=created_at_i>${since},points>10&hitsPerPage=30`,
  );
  if (!res.ok) return { items: [], source: `hacker-news http ${res.status}` };
  const items = hackerNewsFrom(await res.json(), name);
  return { items, source: `hacker-news ok, ${items.length} items` };
}

let cacheClient: SupabaseClient | null = null;
function cache(): SupabaseClient | null {
  if (cacheClient) return cacheClient;
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  cacheClient = createClient(url, key);
  return cacheClient;
}

// The cache only ever helps: if it cannot be read or written, the function
// answers exactly as it did without one.
async function readCache(key: string) {
  try {
    const { data } = await cache()!
      .from('tool_updates_cache')
      .select('kind,items,source,fetched_at')
      .eq('cache_key', key)
      .maybeSingle();
    return data as { kind: string; items: Item[]; source: string; fetched_at: string } | null;
  } catch {
    return null;
  }
}

async function writeCache(key: string, kind: string, items: Item[], source: string) {
  try {
    await cache()!.from('tool_updates_cache').upsert({
      cache_key: key,
      kind,
      items,
      source,
      fetched_at: new Date().toISOString(),
    });
  } catch {
    // See readCache.
  }
}

// Public on purpose — every tool page asks for its release notes — but each
// call spends part of GitHub's unauthenticated budget of 60 requests an hour,
// which is shared by everything this project runs from the same address. One
// caller looping over it would empty that budget and blank "What's new" for
// every visitor. A person reading tool pages will not come near 30 a minute.
const limiter = new InMemoryLimiter(30, 60_000);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  if (!limiter.take(callerKey(req, 'tool-updates'))) {
    return tooManyRequests(60);
  }

  try {
    const { name, source_url, slug } = await req.json();
    const toolName = (name ?? '').toString().trim();
    if (!toolName) return json({ data: [], error: 'name required' }, 400);

    const repo = repoFrom(source_url?.toString(), slug?.toString());
    const key = cacheKey(repo, toolName);

    // Answered in the last 12 hours: serve that, and ask nobody.
    const cached = await readCache(key);
    const use = cacheUse(cached?.fetched_at, Date.now());
    if (cached && use === 'fresh') {
      return json({
        data: aboutTool(cached.items as Item[], toolName),
        kind: cached.kind,
        source: `cache (${cached.source})`,
        error: null,
      });
    }

    let items: Item[] = [];
    let kind = 'news';
    if (repo) {
      items = await githubReleases(repo.owner, repo.repo).catch(() => []);
      if (items.length > 0) kind = 'releases';
    }
    // No repo, or repo has no published releases → feature-announcement fallback.
    let source = kind === 'releases' ? 'github ok' : undefined;
    if (items.length === 0) {
      const news = await featureNews(toolName).catch((e) => ({
        items: [] as Item[],
        source: `google-news failed: ${String(e).slice(0, 120)}`,
      }));
      items = aboutTool(news.items, toolName);
      source = news.source;
    }
    // Google News turns this address away about half the time. Ask Hacker
    // News rather than show nothing.
    if (items.length === 0 && !(source ?? '').startsWith('google-news ok')) {
      const hn = await hackerNews(toolName).catch((e) => ({
        items: [] as Item[],
        source: `hacker-news failed: ${String(e).slice(0, 120)}`,
      }));
      items = hn.items;
      source = `${source}; ${hn.source}`;
    }

    const answered = items.length > 0 || (source ?? '').includes(' ok');
    if (answered) {
      items = newestFirst(items).slice(0, 10);
      await writeCache(key, kind, items, source ?? '');
    } else if (cached && use === 'fallback') {
      // Every source refused: last week's answer beats an empty section.
      return json({
        data: aboutTool(cached.items as Item[], toolName),
        kind: cached.kind,
        source: `stale cache; ${source}`,
        error: null,
      });
    }

    return json({ data: items, kind, source, error: null });
  } catch (err) {
    return failure('tool-updates', err, 500);
  }
});
