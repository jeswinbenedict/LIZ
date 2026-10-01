-- ============================================================================
-- Liz — one row per product site. Migration 0049. Safe to re-run.
--
-- Fourteen products were published twice. The scraper deduplicated on a hash
-- of the exact listing URL, so the same launch reached through a URL with a
-- tracking parameter, a trailing slash or a different listing became a second
-- row (with a slug suffixed to dodge the first one's).
--
-- site_key is the product's address reduced to host and path: no scheme, no
-- www, no query or fragment, no trailing slash, lower case. The scraper checks
-- it before writing (liz_scraper.pipeline), and dedupe_tools hides the
-- duplicates already published. Kept in step with normalize.site_key().
-- ============================================================================

alter table public.tools
  add column if not exists site_key text
  generated always as (
    nullif(
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(coalesce(website_url, '')), '^[a-z][a-z0-9+.-]*://(www\.)?', ''),
          '[?#].*$', ''),
        '/+$', ''),
      '')
  ) stored;

create index if not exists idx_tools_site_key on public.tools (site_key);
