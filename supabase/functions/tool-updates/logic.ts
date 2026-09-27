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
