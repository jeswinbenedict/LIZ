// What the laptop scraper may write, decided without a database so it can be
// tested. The laptop holds a key for this function only (LIZ_INGEST_KEY),
// instead of the service role key that could read and write everything.

/// Columns a new or re-scraped listing may carry — exactly what
/// liz_scraper.normalize and the pipeline produce.
export const UPSERT_COLUMNS = new Set([
  'name', 'slug', 'tagline', 'description', 'website_url', 'logo_url',
  'category', 'tags', 'platforms', 'pricing_type', 'price_note', 'source',
  'source_url', 'launched_at', 'content_hash', 'status', 'hold_reason',
  'hn_id', 'hn_points', 'image_url',
]);

/// Columns retry_held may change on a held listing.
export const HELD_UPDATE_COLUMNS = new Set([
  'name', 'tagline', 'description', 'website_url', 'logo_url', 'category',
  'platforms', 'pricing_type', 'source', 'source_url', 'status', 'hold_reason',
]);

/// The scraper publishes or holds; hiding is moderation.
const STATUSES = new Set(['published', 'pending']);

export const MAX_ROWS = 100;

export type Row = Record<string, unknown>;

/// A row cut down to [allowed] columns, or a reason it is refused.
export function cleanRow(row: unknown, allowed: Set<string>): Row | string {
  if (!row || typeof row !== 'object' || Array.isArray(row)) return 'not an object';
  const out: Row = {};
  for (const [key, value] of Object.entries(row as Row)) {
    if (allowed.has(key)) out[key] = value;
  }
  if ('status' in out && !STATUSES.has(String(out.status))) {
    return `status ${String(out.status)} is not allowed`;
  }
  return out;
}

/// New listings to upsert: each must name its content_hash, and none may
/// rewrite a listing that is already published — the scraper skips those
/// itself, so a key that tries is not the scraper.
export function rowsToUpsert(
  rows: unknown,
  publishedHashes: Set<string>,
): { rows: Row[]; refused: string[] } {
  const refused: string[] = [];
  const out: Row[] = [];
  if (!Array.isArray(rows)) return { rows: [], refused: ['rows must be a list'] };
  for (const raw of rows.slice(0, MAX_ROWS)) {
    const row = cleanRow(raw, UPSERT_COLUMNS);
    if (typeof row === 'string') {
      refused.push(row);
      continue;
    }
    const hash = row.content_hash;
    if (typeof hash !== 'string' || !hash) {
      refused.push('missing content_hash');
      continue;
    }
    if (publishedHashes.has(hash)) {
      refused.push(`${hash} is published`);
      continue;
    }
    out.push(row);
  }
  if (rows.length > MAX_ROWS) refused.push(`only ${MAX_ROWS} rows per call`);
  return { rows: out, refused };
}

/// Strings only, at most [max] of them: the lists the lookups take.
export function stringList(value: unknown, max = 500): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === 'string' && v.length > 0)
    .slice(0, max);
}
