-- ============================================================================
-- Liz — Technology News Feed: Realtime + (optional) scheduled ingestion.
-- Migration 0004. Safe to re-run.
-- ============================================================================

-- 1) Enable Supabase Realtime on the news table so newly-ingested articles are
--    pushed to connected clients instantly (the app's live feed).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'news'
  ) then
    alter publication supabase_realtime add table public.news;
  end if;
end $$;

-- Helps the feed query (already created in 0001, repeated here for fresh setups).
create index if not exists idx_news_status_pub on news (status, published_at desc);

-- ----------------------------------------------------------------------------
-- 2) OPTIONAL in-database scheduler (pg_cron + pg_net).
--    The RECOMMENDED scheduler is the free GitHub Actions workflow
--    (.github/workflows/fetch-news.yml) — it keeps keys out of the database.
--    If you'd rather schedule inside Postgres, uncomment the block below and
--    replace <PROJECT_REF> and <SERVICE_ROLE_KEY>. Prefer storing the key in
--    Supabase Vault rather than inline.
-- ----------------------------------------------------------------------------
--
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule(
--   'fetch-news-hourly',
--   '0 * * * *',                       -- top of every hour
--   $$
--     select net.http_post(
--       url     := 'https://<PROJECT_REF>.functions.supabase.co/fetch-news',
--       headers := jsonb_build_object(
--         'Content-Type', 'application/json',
--         'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
--       ),
--       body    := '{}'::jsonb
--     );
--   $$
-- );
