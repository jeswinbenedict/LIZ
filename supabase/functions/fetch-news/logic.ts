const NAMED_ENTITIES: Record<string, string> = {
  nbsp: ' ', lt: '<', gt: '>', quot: '"', apos: "'",
  ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’',
  mdash: '—', ndash: '–', hellip: '…', amp: '&',
};

export function fromCodePoint(code: number): string | null {
  if (!Number.isFinite(code) || code < 0 || code > 0x10ffff) return null;
  try {
    return String.fromCodePoint(code);
  } catch (_) {
    return null;
  }
}

/// Feeds encode punctuation in whichever form they please — &quot;, &#34; and
/// &#x22; all mean the same double quote — so decode numeric escapes generically
/// rather than listing every spelling.
export function decodeEntities(text: string): string {
  return text
    .replace(/&#(\d+);/g, (m, d) => fromCodePoint(parseInt(d, 10)) ?? m)
    .replace(/&#[xX]([0-9a-fA-F]+);/g, (m, h) => fromCodePoint(parseInt(h, 16)) ?? m)
    .replace(/&([a-zA-Z]+);/g, (m, n) => NAMED_ENTITIES[n.toLowerCase()] ?? m);
}

/// Feed titles are plain text but still arrive entity-encoded — "Instagram&#8217;s
/// new logo" — so they need decoding even though there are no tags to strip.
export function cleanTitle(raw: string): string {
  return decodeEntities(raw).replace(/\s+/g, ' ').trim();
}

/// A feed's HTML as plain text, whole.
export function htmlToText(html: string): string {
  // Tags first, then entities. Decoding first would turn an article's own
  // "&lt;div&gt;" into markup that the tag pass then deletes, losing text the
  // author meant to show. Note the consequence: an encoded tag survives as
  // literal characters, so a snippet is plain text and must be rendered as
  // such — it is not sanitised HTML.
  return decodeEntities(html.replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

/// A snippet is at most 300 characters.
export function clip(text: string): string {
  return text.length > 300 ? `${text.slice(0, 297)}…` : text;
}

export function stripHtml(html: string): string {
  return clip(htmlToText(html));
}

/// The snippet stored for a story. Hacker News's footer goes before the cut:
/// a long article URL used to push the footer past character 300, the cut
/// left half of it, and half a footer no longer matched.
export function newsSnippet(html: string, source: string): string {
  const text = htmlToText(html);
  return clip(source === 'hackernews' ? stripHnFooter(text) : text);
}

/// hnrss.org describes every front-page story with the same footer — "Article
/// URL: … Comments URL: … Points: 8 # Comments: 2" — which says nothing about
/// the story and read as its summary on the News page. Drop it; an Ask HN
/// post keeps the text written above it.
export function stripHnFooter(snippet: string): string {
  return snippet
    // From "Article URL: … Comments URL:" to the end is all footer, whole
    // or cut short.
    .replace(/\s*Article URL:\s*\S+\s*Comments URL:[\s\S]*$/i, '')
    .trim();
}
