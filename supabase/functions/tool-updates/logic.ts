// Pure parts of tool-updates: where a tool's releases live, and how GitHub's
// and Google News's answers become the items a tool page shows. Split out so
// they can be tested without the network.

export interface Item {
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

export function decodeXml(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(n, 10)))
    .trim();
}

/** The GitHub repository whose releases describe this tool, if there is one. */
export function repoFrom(
  sourceUrl?: string,
  slug?: string,
): { owner: string; repo: string } | null {
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

/** The first line of prose in a release body, stripped of markdown. */
export function firstLine(body?: string): string | null {
  if (!body) return null;
  const clean = body
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#>*_`\-]+/g, ' ')
    .replace(/\r/g, '')
    .split('\n').map((l) => l.trim()).filter(Boolean)[0] ?? '';
  return clean ? clean.slice(0, 160) : null;
}

/** GitHub's releases response as items, drafts left out. */
export function releasesFrom(data: unknown): Item[] {
  if (!Array.isArray(data)) return [];
  return data
    .filter((r: { draft?: boolean }) => !r.draft)
    .map((r: {
      name?: string;
      tag_name?: string;
      body?: string;
      html_url: string;
      published_at?: string;
    }) => ({
      title: (r.name && r.name.trim()) ? r.name : (r.tag_name ?? 'Release'),
      note: firstLine(r.body),
      url: r.html_url,
      source: 'GitHub Releases',
      published_at: r.published_at ?? null,
    }));
}

/**
 * Whether [title] names the tool as a whole word, in any script: letters and
 * digits either side mean it is part of a longer word ("Cursor" in "Cursors"
 * or "RecursorAI").
 */
export function namesTool(title: string, name: string): boolean {
  const n = name.trim();
  if (!n) return false;
  const escaped = n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^\\p{L}\\p{N}])${escaped}($|[^\\p{L}\\p{N}])`, 'iu').test(title);
}

/** Headlines that differ only in case and punctuation are one story. */
function storyKey(title: string): string {
  return title.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

/**
 * Items whose headline names the tool, one per story.
 *
 * Google News matches a quoted name anywhere in an article, so a story about
 * another company that mentions the tool once in its body came back too — on
 * 1 October ElevenLabs' page listed "Ramp Launches in the UK". Applied to
 * cached answers as well, so those go the moment this is deployed.
 */
export function aboutTool(items: Item[], name: string): Item[] {
  const seen = new Set<string>();
  return items.filter((item) => {
    if (item.source === 'GitHub Releases') return true;
    if (!namesTool(item.title, name)) return false;
    const key = storyKey(item.title);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/** A Google News RSS answer as items, at most [limit]. */
export function newsFrom(xml: string, limit = 10): Item[] {
  const items: Item[] = [];
  const itemRe = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) && items.length < limit) {
    const b = m[1];
    const rawTitle = decodeXml(b.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? '');
    const link = decodeXml(b.match(/<link>([\s\S]*?)<\/link>/)?.[1] ?? '');
    const pub = (b.match(/<pubDate>([\s\S]*?)<\/pubDate>/)?.[1] ?? '').trim();
    const source = decodeXml(b.match(/<source[^>]*>([\s\S]*?)<\/source>/)?.[1] ?? '');
    if (!rawTitle || !link) continue;
    // Google News appends " - Publisher" to every headline; the source is
    // shown separately, so say it once.
    let title = rawTitle;
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, title.length - source.length - 3);
    }
    const when = pub ? new Date(pub) : null;
    items.push({
      title,
      note: null,
      url: link,
      source: source || 'Google News',
      published_at: when && !isNaN(when.getTime()) ? when.toISOString() : null,
    });
  }
  return items;
}

/** Newest first; undated items last. */
export function newestFirst(items: Item[]): Item[] {
  return [...items].sort((a, b) =>
    (b.published_at ?? '').localeCompare(a.published_at ?? '')
  );
}

/**
 * Hacker News stories about a tool, from the Algolia HN search API.
 *
 * The fallback when Google News turns this address away. A search on the name
 * matches plenty that is not about the tool, so only stories with the name as
 * a whole word in the title count, and not Show/Ask/Tell HN posts, which are
 * about someone else's project that mentions it.
 */
export function hackerNewsFrom(data: unknown, name: string, limit = 10): Item[] {
  const hits = (data as { hits?: unknown })?.hits;
  if (!Array.isArray(hits) || !name.trim()) return [];
  const items: Item[] = [];
  for (const h of hits as Record<string, unknown>[]) {
    const title = typeof h.title === 'string' ? h.title.trim() : '';
    if (!title || !namesTool(title, name) || /^(show|ask|tell) hn\b/i.test(title)) continue;
    const id = String(h.objectID ?? '');
    items.push({
      title,
      note: null,
      url: typeof h.url === 'string' && h.url ? h.url : `https://news.ycombinator.com/item?id=${id}`,
      source: 'Hacker News',
      published_at: typeof h.created_at === 'string' ? h.created_at : null,
    });
    if (items.length >= limit) break;
  }
  return items;
}

/** Cache key for a tool's updates: its repository, or its name. */
export function cacheKey(repo: { owner: string; repo: string } | null, name: string): string {
  return repo
    ? `gh:${repo.owner}/${repo.repo}`.toLowerCase()
    : `news:${name.trim().toLowerCase()}`;
}

export const FRESH_FOR_MS = 12 * 60 * 60 * 1000;
export const STALE_UP_TO_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * What to do with a cached answer: serve it as is, fetch a new one but keep
 * this as a fallback, or ignore it.
 */
export function cacheUse(
  fetchedAt: string | null | undefined,
  now: number,
): 'fresh' | 'fallback' | 'none' {
  if (!fetchedAt) return 'none';
  const age = now - new Date(fetchedAt).getTime();
  if (!Number.isFinite(age) || age < 0) return 'none';
  if (age < FRESH_FOR_MS) return 'fresh';
  if (age < STALE_UP_TO_MS) return 'fallback';
  return 'none';
}
