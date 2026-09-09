-- ============================================================================
-- Liz — take the catalog back out of the realtime publication. Migration 0018.
--
-- 0017 added `tools` so Discover could stream changes. Measuring it showed the
-- idea does not pay for itself here:
--
--   * Approving a tool is an UPDATE, and with RLS enabled Postgres must compare
--     the policy against the old row — which needs REPLICA IDENTITY FULL. On a
--     table carrying vector(384) that writes the entire old row, embedding
--     included, to WAL on every ingestion update.
--   * The catalog changes on a daily cron. Almost nobody is looking at Discover
--     in the second a tool lands, so the stream mostly carries nothing.
--   * The feed is a family provider, so each category and sort combination
--     opened its own channel — a handful of sockets per browsing session for
--     updates that arrive once a day.
--
-- News keeps its subscription: articles arrive hourly, the feed is a single
-- channel, and they are inserts, which stream without the replica-identity
-- cost. Discover refreshes when the tab regains focus instead, which covers
-- the case that actually happens — someone coming back to a page left open.
-- ============================================================================

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tools'
  ) then
    alter publication supabase_realtime drop table public.tools;
  end if;
end $$;
