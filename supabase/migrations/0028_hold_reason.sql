-- ============================================================================
-- Liz — say why a tool is not published. Migration 0028.
--
-- Ingestion writes every find as `pending` and the quality gate now decides
-- what gets published. But `pending` on its own does not distinguish "held
-- because we could not reach the product page" from "nobody has looked at this
-- yet", and that distinction is the difference between a queue that needs a
-- person and one that needs nothing.
--
-- Recording the gate's own reason keeps a second copy of the rule out of SQL.
-- The health check below asks a question SQL can answer on its own — are there
-- pending rows nothing explains? — instead of re-deriving what counts as
-- publishable and drifting from the Python.
-- ============================================================================

alter table tools add column if not exists hold_reason text;

comment on column tools.hold_reason is
  'Why the quality gate held this row back, or null when it was published or '
  'predates the gate. Written by the scraper; see liz_scraper/quality.py.';

-- The admin queue reads pending rows by reason, newest first.
create index if not exists idx_tools_pending_reason
  on tools (status, created_at desc)
  where status = 'pending';

-- ----------------------------------------------------------------------------
-- Health: a backlog nothing accounts for.
--
-- Rows held for a recorded reason are working as designed — 216 Product Hunt
-- entries sit behind a 403 that no amount of attention will fix from a cloud
-- IP. Rows sitting pending with no reason at all mean something wrote around
-- the gate, and those are the ones worth a person's time.
-- ----------------------------------------------------------------------------
create or replace function system_health()
returns table (
  signal      text,
  status      text,
  value       numeric,
  detail      text
)
language sql
stable
security definer
set search_path = public
as $$
  with newest_tool as (
    select extract(epoch from now() - max(created_at)) / 3600 as hours
      from tools where status = 'published'
  ),
  newest_news as (
    select extract(epoch from now() - max(published_at)) / 3600 as hours
      from news where status = 'published'
  ),
  published as (
    select count(*)::numeric as n from tools where status = 'published'
  ),
  embedded as (
    select count(*)::numeric as n from tools
     where status = 'published' and embedding is not null
  ),
  summarisable as (
    select count(*)::numeric as n from tools
     where status = 'published'
       and coalesce(description, '') <> ''
       and summary_attempts < 3
  ),
  summarised as (
    select count(*)::numeric as n from tools
     where status = 'published'
       and coalesce(description, '') <> ''
       and summary_attempts < 3
       and coalesce(jsonb_array_length(
             case when jsonb_typeof(ai_summary) = 'array'
                  then ai_summary else '[]'::jsonb end
           ), 0) > 0
  ),
  written_off as (
    select count(*)::numeric as n from tools
     where status = 'published' and summary_attempts >= 3
  ),
  unexplained as (
    select count(*)::numeric as n from tools
     where status = 'pending' and hold_reason is null
  ),
  recent_errors as (
    select count(*)::numeric as n from error_events
     where created_at > now() - interval '24 hours'
  ),
  open_reports as (
    select count(*)::numeric as n from reports where status = 'open'
  )
  select 'catalog_freshness_hours',
         case when hours is null then 'fail'
              when hours > 72 then 'fail'
              when hours > 36 then 'warn'
              else 'ok' end,
         round(coalesce(hours, -1)::numeric, 1),
         'Hours since the newest published tool. The fetch runs daily.'
    from newest_tool
  union all
  select 'news_freshness_hours',
         case when hours is null then 'fail'
              when hours > 24 then 'fail'
              when hours > 6  then 'warn'
              else 'ok' end,
         round(coalesce(hours, -1)::numeric, 1),
         'Hours since the newest published article. The pull runs hourly.'
    from newest_news
  union all
  select 'published_tools',
         case when n < 1 then 'fail' when n < 25 then 'warn' else 'ok' end,
         n,
         'Tools visible in the catalog.'
    from published
  union all
  select 'embedding_coverage_pct',
         case when p.n = 0 then 'fail'
              when e.n / p.n < 0.50 then 'fail'
              when e.n / p.n < 0.90 then 'warn'
              else 'ok' end,
         round(case when p.n = 0 then 0 else 100 * e.n / p.n end, 1),
         'Published tools carrying a search embedding.'
    from published p, embedded e
  union all
  select 'ai_summary_coverage_pct',
         case when c.n = 0 then 'ok'
              when s.n / c.n < 0.75 then 'warn'
              else 'ok' end,
         round(case when c.n = 0 then 100 else 100 * s.n / c.n end, 1),
         'Summarised, of the published tools that can be summarised.'
    from summarisable c, summarised s
  union all
  select 'summaries_written_off',
         case when n > 25 then 'warn' else 'ok' end,
         n,
         'Tools the summariser gave up on after three empty results.'
    from written_off
  union all
  select 'unexplained_backlog',
         case when n > 100 then 'fail' when n > 20 then 'warn' else 'ok' end,
         n,
         'Pending tools with no recorded reason — nothing is reviewing these.'
    from unexplained
  union all
  select 'client_errors_24h',
         case when n > 100 then 'fail' when n > 10 then 'warn' else 'ok' end,
         n,
         'Crash reports filed by clients in the last day.'
    from recent_errors
  union all
  select 'open_reports',
         case when n > 25 then 'warn' else 'ok' end,
         n,
         'Moderation reports waiting on someone.'
    from open_reports;
$$;

grant execute on function system_health() to authenticated;
