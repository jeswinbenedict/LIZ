-- ============================================================================
-- Liz — logos served from Storage. Migration 0048. Safe to re-run.
--
-- Every logo used to be fetched through the `logo` Edge Function on every
-- first view: twenty-odd function calls per visit to Discover, none of them
-- cached at the edge. On a free plan's monthly allowance that runs out at
-- roughly twenty thousand first-time visitors — the first wall Liz would hit.
--
-- `python -m liz_scraper.store_logos` now fetches each logo once (through the
-- same proxy, with its SSRF and SVG rules), shrinks it to a 128-pixel WebP of
-- a few kilobytes, and stores it here. tools.logo_url then points at the
-- public object, which the Storage CDN serves with a one-year cache. The
-- proxy remains for anything not stored yet.
--
-- File names carry a content hash, so a changed logo gets a new URL rather
-- than fighting a year-long cache.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos', 'logos', true, 262144, array['image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
