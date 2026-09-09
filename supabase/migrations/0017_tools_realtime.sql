-- ============================================================================
-- Liz — live catalog updates. Migration 0017. Safe to re-run.
--
-- News already streamed to connected clients; the catalog did not, so a tool
-- published by the ingestion pipeline (or approved from the admin panel) stayed
-- invisible until the visitor reloaded the page.
--
-- Both events matter here: an insert is a newly ingested tool, and an update is
-- how a pending tool becomes published — approval is a status change, not a new
-- row, so insert alone would miss it.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tools'
  ) then
    alter publication supabase_realtime add table public.tools;
  end if;
end $$;
