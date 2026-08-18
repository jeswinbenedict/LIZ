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

interface Item {
  title: string;
  note: string | null;
  url: string;
  source: string;
  published_at: string | null;
}

// Curated tools that are closed-source in listing but have a prominent repo.
const CURATED_REPO: Record<string, string> = {
  'n8n': 'n8n-io/n8n',
  'hugging-face': 'huggingface/transformers',
  'stability-ai': 'Stability-AI/generative-models',
};

function decodeXml(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(n, 10)))
    .trim();
}

function repoFrom(sourceUrl?: string, slug?: string): { owner: string; repo: string } | null {
  if (sourceUrl) {
    const m = sourceUrl.match(/github\.com\/([^/]+)\/([^/#?]+)/i);
    if (m) return { owner: m[1], repo: m[2].replace(/\.git$/, '') };
  }
  if (slug && CURATED_REPO[slug]) {
    const [owner, repo] = CURATED_REPO[slug].split('/');
    return { owner, repo };
  }
  return null;
}

function firstLine(body?: string): string | null {
  if (!body) return null;
  const clean = body
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#>*_`\-]+/g, ' ')
    .replace(/\r/g, '')
    .split('\n').map((l) => l.trim()).filter(Boolean)[0] ?? '';
  return clean ? clean.slice(0, 160) : null;
}

async function githubReleases(owner: string, repo: string): Promise<Item[]> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/releases?per_page=8`,
    { headers: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'liz-tool-updates' } },
  );
  if (!res.ok) return [];
  const data = await res.json();
  if (!Array.isArray(data)) return [];
  return data
    .filter((r: { draft?: boolean }) => !r.draft)
    .map((r: { name?: string; tag_name?: string; body?: string; html_url: string; published_at: string }) => ({
      title: (r.name && r.name.trim()) ? r.name : (r.tag_name ?? 'Release'),
      note: firstLine(r.body),
      url: r.html_url,
      source: 'GitHub Releases',
      published_at: r.published_at ?? null,
    }));
}

async function featureNews(name: string): Promise<Item[]> {
  const q = `"${name}" (update OR "new feature" OR launches OR introduces OR "rolling out" OR announces) when:90d`;
  const res = await fetch(
    `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=en-US&gl=US&ceid=US:en`,
    { headers: { 'User-Agent': 'Mozilla/5.0 (Liz)' } },
  );
  if (!res.ok) return [];
  const xml = await res.text();
  const items: Item[] = [];
  const itemRe = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) && items.length < 10) {
    const b = m[1];
    const rawTitle = decodeXml(b.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? '');
    const link = decodeXml(b.match(/<link>([\s\S]*?)<\/link>/)?.[1] ?? '');
    const pub = (b.match(/<pubDate>([\s\S]*?)<\/pubDate>/)?.[1] ?? '').trim();
    const source = decodeXml(b.match(/<source[^>]*>([\s\S]*?)<\/source>/)?.[1] ?? '');
    if (!rawTitle || !link) continue;
    let title = rawTitle;
    if (source && title.endsWith(` - ${source}`)) title = title.slice(0, title.length - source.length - 3);
    items.push({
      title,
      note: null,
      url: link,
      source: source || 'Google News',
      published_at: pub ? new Date(pub).toISOString() : null,
    });
  }
  return items;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

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

    items.sort((a, b) => (b.published_at ?? '').localeCompare(a.published_at ?? ''));
    return json({ data: items.slice(0, 10), kind, error: null });
  } catch (err) {
    return json({ data: [], error: String(err) }, 500);
  }
});
