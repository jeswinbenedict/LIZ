// POST /scraper-ingest — the one door the laptop scraper (n8n, Product Hunt)
// writes through.
//
// The laptop used to hold the service role key, which reads and writes every
// table: profiles, notifications, storage, everything. It needs four things,
// all on `tools`, so it now holds LIZ_INGEST_KEY for this function instead,
// and a stolen laptop can at worst submit tool listings.
//
//   {"action": "existing", "hashes": [...], "site_keys": [...]}
//      -> published content_hashes, and site_key -> content_hash
//   {"action": "upsert", "rows": [...]}       new or re-scraped listings;
//      never one that is already published (logic.ts)
//   {"action": "held", "marker": "...", "limit": 50}
//      -> pending rows whose hold_reason names the marker
//   {"action": "update_held", "id": "...", "update": {...}}
//      only a row that is still pending, only scraper columns
//
// Auth: header x-liz-ingest must equal the INGEST_KEY secret (48 random
// characters, compared in constant time). verify_jwt is off: the laptop holds
// no Supabase key at all.
//
// Deploy: supabase functions deploy scraper-ingest --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { constantTimeEquals } from '../_shared/auth.ts';
import { json, failure } from '../_shared/cors.ts';
import {
  cleanRow,
  HELD_UPDATE_COLUMNS,
  rowsToUpsert,
  stringList,
} from './logic.ts';

const HELD_COLUMNS = 'id,name,tagline,description,website_url,source,source_url,' +
  'logo_url,category,platforms,pricing_type,hold_reason';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ data: null, error: 'POST only' }, 405);

  const expected = Deno.env.get('INGEST_KEY') ?? '';
  const presented = req.headers.get('x-liz-ingest') ?? '';
  if (expected.length < 32 || !constantTimeEquals(presented, expected)) {
    return json({ data: null, error: 'Not authorized' }, 401);
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const body = await req.json().catch(() => ({}));
    switch (body.action) {
      case 'existing': {
        const hashes = stringList(body.hashes);
        const keys = stringList(body.site_keys);
        const published: string[] = [];
        const sites: Record<string, string> = {};
        if (hashes.length) {
          const { data, error } = await db.from('tools').select('content_hash')
            .in('content_hash', hashes).eq('status', 'published');
          if (error) throw error;
          for (const r of data ?? []) published.push(r.content_hash);
        }
        if (keys.length) {
          const { data, error } = await db.from('tools').select('site_key,content_hash')
            .in('site_key', keys).eq('status', 'published');
          if (error) throw error;
          for (const r of data ?? []) sites[r.site_key] = r.content_hash;
        }
        return json({ data: { published, sites }, error: null });
      }

      case 'upsert': {
        const offered = stringList(
          (Array.isArray(body.rows) ? body.rows : []).map((r: { content_hash?: unknown }) =>
            r?.content_hash
          ),
        );
        const { data: live, error: liveErr } = await db.from('tools').select('content_hash')
          .in('content_hash', offered.length ? offered : ['-']).eq('status', 'published');
        if (liveErr) throw liveErr;
        const { rows, refused } = rowsToUpsert(
          body.rows,
          new Set((live ?? []).map((r) => r.content_hash)),
        );
        if (rows.length) {
          const { error } = await db.from('tools')
            .upsert(rows, { onConflict: 'content_hash' });
          if (error) return failure('scraper-ingest', error, 400);
        }
        return json({ data: { written: rows.length, refused }, error: null });
      }

      case 'held': {
        const marker = typeof body.marker === 'string' ? body.marker : '';
        const limit = Math.min(Math.max(Number(body.limit) || 50, 1), 200);
        if (!marker) return json({ data: null, error: 'marker required' }, 400);
        const { data, error } = await db.from('tools').select(HELD_COLUMNS)
          .eq('status', 'pending').like('hold_reason', `%${marker}%`)
          .order('created_at', { ascending: false }).limit(limit);
        if (error) throw error;
        return json({ data: data ?? [], error: null });
      }

      case 'update_held': {
        const id = typeof body.id === 'string' ? body.id : '';
        const update = cleanRow(body.update, HELD_UPDATE_COLUMNS);
        if (!id || typeof update === 'string') {
          return json({ data: null, error: typeof update === 'string' ? update : 'id required' }, 400);
        }
        // Only a row that is still held: a published or hidden listing is not
        // the scraper's to change.
        const { data, error } = await db.from('tools').update(update)
          .eq('id', id).eq('status', 'pending').select('id');
        if (error) return failure('scraper-ingest', error, 400);
        return json({ data: { updated: (data ?? []).length }, error: null });
      }

      default:
        return json({ data: null, error: 'unknown action' }, 400);
    }
  } catch (err) {
    return failure('scraper-ingest', err, 500);
  }
});
