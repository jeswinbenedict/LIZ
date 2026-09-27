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

import { corsHeaders, json } from '../_shared/cors.ts';
import { callerKey, InMemoryLimiter, tooManyRequests } from '../_shared/rate_limit.ts';
import { type Item, newestFirst, newsFrom, releasesFrom, repoFrom } from './logic.ts';

async function githubReleases(owner: string, repo: string): Promise<Item[]> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/releases?per_page=8`,
    { headers: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'liz-tool-updates' } },
  );
  if (!res.ok) return [];
  return releasesFrom(await res.json());
}

async function featureNews(name: string): Promise<Item[]> {
  const q = `"${name}" (update OR "new feature" OR launches OR introduces OR "rolling out" OR announces) when:90d`;
  const res = await fetch(
    `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=en-US&gl=US&ceid=US:en`,
    { headers: { 'User-Agent': 'Mozilla/5.0 (Liz)' } },
  );
  if (!res.ok) return [];
  return newsFrom(await res.text());
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

    let items: Item[] = [];
    let kind = 'news';
    if (repo) {
      items = await githubReleases(repo.owner, repo.repo).catch(() => []);
      if (items.length > 0) kind = 'releases';
    }
    // No repo, or repo has no published releases → feature-announcement fallback.
    if (items.length === 0) {
      items = await featureNews(toolName).catch(() => []);
    }

    return json({ data: newestFirst(items).slice(0, 10), kind, error: null });
  } catch (err) {
    return json({ data: [], error: String(err) }, 500);
  }
});
