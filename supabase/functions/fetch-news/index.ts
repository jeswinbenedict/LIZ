// POST /fetch-news — ingest the latest technology news into the `news` table.
//
// Sources are all FREE + OPEN:
//   • RSS/Atom feeds (open standard) — TechCrunch, The Verge, Ars Technica,
//     Wired, Engadget, MIT Technology Review, Hacker News (via hnrss.org).
//   • Dev.to public API (free, no key).
//   • deno-dom scraping fallback for sources without a feed (see scrapeHeadlines).
//
// Tools: `@mikaelporttila/rss` (parseFeed) and `deno-dom` — both widely-adopted
// open-source Deno libraries. For JS-heavy sites that need a real browser, run a
// Playwright/Cheerio worker (n8n or a small VPS) that writes to this same table.
//
// Dedupe is by article URL (news.url is unique) via upsert + ignoreDuplicates,
// so re-running is safe and only new articles are inserted. New rows are
// published immediately and pushed to clients over Supabase Realtime.
//
// Invoke hourly via GitHub Actions or pg_cron (see .github/workflows + docs).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { parseFeed } from 'https://deno.land/x/rss@1.1.2/mod.ts';
import { DOMParser } from 'https://deno.land/x/deno_dom@v0.1.45/deno-dom-wasm.ts';
import { preflight, requireServiceRole } from '../_shared/auth.ts';
import { json } from '../_shared/cors.ts';
import { cleanTitle, stripHnFooter, stripHtml } from './logic.ts';

interface Article {
  title: string;
  url: string;
  snippet: string;
  source: string;
  image_url: string | null;
  published_at: string;
}

const FEEDS: { source: string; url: string }[] = [
  { source: 'techcrunch', url: 'https://techcrunch.com/feed/' },
  { source: 'theverge', url: 'https://www.theverge.com/rss/index.xml' },
  { source: 'arstechnica', url: 'https://feeds.arstechnica.com/arstechnica/technology-lab' },
  { source: 'wired', url: 'https://www.wired.com/feed/rss' },
  { source: 'engadget', url: 'https://www.engadget.com/rss.xml' },
  // VentureBeat was here until September 2026, when it put its feed behind a
  // bot challenge that answers 429 to every automated reader. Getting past a
  // challenge is evading it, so the source was replaced rather than worked
  // around; its old Feedburner mirror had stopped updating anyway.
  { source: 'techreview', url: 'https://www.technologyreview.com/topic/artificial-intelligence/feed' },
  { source: 'hackernews', url: 'https://hnrss.org/frontpage' },
];

const MAX_PER_SOURCE = 10;

// deno-lint-ignore no-explicit-any
function pickImage(entry: any): string | null {
  return (
    entry?.attachments?.[0]?.url ??
    entry?.['media:content']?.url ??
    entry?.['media:thumbnail']?.url ??
    null
  );
}

async function fromRss(feed: { source: string; url: string }): Promise<Article[]> {
  const res = await fetch(feed.url, {
    headers: { 'user-agent': 'LizNewsBot/1.0 (+https://liz.app)' },
  });
  if (!res.ok) throw new Error(`${feed.source} ${res.status}`);
  const xml = await res.text();
  const parsed = await parseFeed(xml);
  const out: Article[] = [];
  for (const entry of (parsed.entries ?? []).slice(0, MAX_PER_SOURCE)) {
    // deno-lint-ignore no-explicit-any
    const e = entry as any;
    const title: string = e.title?.value ?? '';
    const url: string = e.links?.[0]?.href ?? e.id ?? '';
    if (!title || !url) continue;
    const raw = stripHtml(e.description?.value ?? e.content?.value ?? '');
    const snippet = feed.source === 'hackernews' ? stripHnFooter(raw) : raw;
    const published =
      e.published instanceof Date
        ? e.published.toISOString()
        : (e.publishedRaw ? new Date(e.publishedRaw) : new Date()).toISOString();
    out.push({
      title: cleanTitle(title),
      url,
      snippet,
      source: feed.source,
      image_url: pickImage(e),
      published_at: published,
    });
  }
  return out;
}

async function fromDevTo(): Promise<Article[]> {
  const res = await fetch('https://dev.to/api/articles?per_page=12&top=1');
  if (!res.ok) throw new Error(`devto ${res.status}`);
  // deno-lint-ignore no-explicit-any
  const items: any[] = await res.json();
  return items.map((a) => ({
    title: cleanTitle(a.title ?? ''),
    url: a.url,
    snippet: stripHtml(a.description ?? ''),
    source: 'dev.to',
    image_url: a.cover_image ?? a.social_image ?? null,
    published_at: a.published_at ?? new Date().toISOString(),
  }));
}

/// Scraping fallback for sources without an RSS feed / API. Uses deno-dom to
/// parse the page and pull anchor headlines matching a CSS selector. Enable a
/// source by adding it to SCRAPE_TARGETS below (respect each site's ToS).
// deno-lint-ignore no-unused-vars
async function scrapeHeadlines(
  source: string,
  pageUrl: string,
  linkSelector: string,
): Promise<Article[]> {
  const res = await fetch(pageUrl, {
    headers: { 'user-agent': 'LizNewsBot/1.0 (+https://liz.app)' },
  });
  if (!res.ok) throw new Error(`${source} ${res.status}`);
  const html = await res.text();
  const doc = new DOMParser().parseFromString(html, 'text/html');
  if (!doc) return [];
  const out: Article[] = [];
  const origin = new URL(pageUrl).origin;
  for (const a of Array.from(doc.querySelectorAll(linkSelector)).slice(0, MAX_PER_SOURCE)) {
    // deno-lint-ignore no-explicit-any
    const el = a as any;
    const title = cleanTitle(el.textContent ?? '');
    let href = el.getAttribute('href') ?? '';
    if (!title || !href) continue;
    if (href.startsWith('/')) href = origin + href;
    if (!href.startsWith('http')) continue;
    out.push({
      title,
      url: href,
      snippet: '',
      source,
      image_url: null,
      published_at: new Date().toISOString(),
    });
  }
  return out;
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // Only cron and CI may start this: it runs with the service role and spends
  // real quota. See _shared/auth.ts.
  const denied = requireServiceRole(req);
  if (denied) return denied;
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const collected: Article[] = [];
    const errors: string[] = [];

    // RSS feeds (run concurrently, tolerate individual failures).
    const rssResults = await Promise.allSettled(FEEDS.map(fromRss));
    rssResults.forEach((r, i) => {
      if (r.status === 'fulfilled') collected.push(...r.value);
      else errors.push(`${FEEDS[i].source}: ${r.reason}`);
    });

    // Dev.to API.
    try {
      collected.push(...(await fromDevTo()));
    } catch (e) {
      errors.push(`dev.to: ${e}`);
    }

    // De-duplicate by URL within this batch.
    const seen = new Set<string>();
    const rows = [];
    for (const a of collected) {
      if (!a.url || seen.has(a.url)) continue;
      seen.add(a.url);
      rows.push({
        title: a.title,
        url: a.url,
        snippet: a.snippet,
        source: a.source,
        image_url: a.image_url,
        published_at: a.published_at,
        content_hash: await sha256(`${a.title.toLowerCase()}|${a.url}`),
        status: 'published',
      });
    }

    if (rows.length === 0) {
      return json({ data: { fetched: 0, errors }, error: null });
    }

    // Insert new articles; skip any whose URL already exists (idempotent).
    const { error } = await supabase
      .from('news')
      .upsert(rows, { onConflict: 'url', ignoreDuplicates: true });
    if (error) return json({ data: { fetched: rows.length }, error: error.message }, 500);

    return json({ data: { fetched: rows.length, sources: FEEDS.length + 1, errors }, error: null });
  } catch (err) {
    return json({ data: null, error: String(err) }, 500);
  }
});
