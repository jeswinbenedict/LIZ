// POST /tool-news — latest real-time news for a specific tool.
//
// Aggregates from FREE, no-key sources so it works for ANY tool name and stays
// current in real time:
//   • Google News RSS search (aggregates thousands of publishers)
//   • Hacker News (Algolia) for tech discussion
//
// Body: { "query": "ChatGPT" }  ->  { data: [{title,url,source,published_at}], error }
// Read-only + public; safe to call from the client for every tool page.

import { corsHeaders, json } from '../_shared/cors.ts';

interface Item {
  title: string;
  url: string;
  source: string;
  published_at: string | null;
}

function decodeXml(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(n, 10)))
    .trim();
}

async function googleNews(query: string): Promise<Item[]> {
  const url =
    `https://news.google.com/rss/search?q=${encodeURIComponent(query + ' when:30d')}` +
    `&hl=en-US&gl=US&ceid=US:en`;
  const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Liz)' } });
  if (!res.ok) return [];
  const xml = await res.text();
  const items: Item[] = [];
  const itemRe = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) && items.length < 8) {
    const b = m[1];
    const rawTitle = decodeXml(b.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? '');
    const link = decodeXml(b.match(/<link>([\s\S]*?)<\/link>/)?.[1] ?? '');
    const pub = (b.match(/<pubDate>([\s\S]*?)<\/pubDate>/)?.[1] ?? '').trim();
    const source = decodeXml(b.match(/<source[^>]*>([\s\S]*?)<\/source>/)?.[1] ?? '');
    if (!rawTitle || !link) continue;
    // Google formats titles as "Headline - Source"; trim the trailing source.
    let title = rawTitle;
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, title.length - source.length - 3);
    }
    items.push({
      title,
      url: link,
      source: source || 'Google News',
      published_at: pub ? new Date(pub).toISOString() : null,
    });
  }
  return items;
}

async function hackerNews(query: string): Promise<Item[]> {
  const url =
    `https://hn.algolia.com/api/v1/search_by_date?query=${encodeURIComponent(query)}` +
    `&tags=story&hitsPerPage=4`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const data = await res.json();
  return (data.hits ?? [])
    .filter((h: { title?: string }) => h.title)
    .map((h: { title: string; url?: string; objectID: string; created_at: string }) => ({
      title: h.title,
      url: h.url || `https://news.ycombinator.com/item?id=${h.objectID}`,
      source: 'Hacker News',
      published_at: h.created_at,
    }));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { query } = await req.json();
    const q = (query ?? '').toString().trim();
    if (!q) return json({ data: [], error: 'query required' }, 400);

    // Fetch both sources in parallel; tolerate either failing.
    const [g, h] = await Promise.all([
      googleNews(q).catch(() => [] as Item[]),
      hackerNews(q).catch(() => [] as Item[]),
    ]);

    // Merge, de-dupe by normalized title, newest first.
    const seen = new Set<string>();
    const merged: Item[] = [];
    for (const it of [...g, ...h]) {
      const key = it.title.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().slice(0, 60);
      if (seen.has(key)) continue;
      seen.add(key);
      merged.push(it);
    }
    merged.sort((a, b) => (b.published_at ?? '').localeCompare(a.published_at ?? ''));

    return json({ data: merged.slice(0, 10), error: null });
  } catch (err) {
    return json({ data: [], error: String(err) }, 500);
  }
});
