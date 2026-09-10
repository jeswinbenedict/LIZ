-- ============================================================================
-- Liz — stop retrying summaries that will never succeed. Migration 0026.
--
-- Scheduling the summariser in 0025 exposed a loop that was harmless while it
-- ran by hand and is not now that it runs every fifteen minutes. Some rows
-- come back with no usable bullets every time — a README that is a badge
-- table, a description that is one line of shell. The function skips them,
-- with a comment saying that writing an empty array "would leave the row in
-- the view forever, retried on every run". Skipping leaves it in the view
-- forever too. Both branches retry, so once the real backlog drains, every run
-- spends its whole batch on the same handful of hopeless rows.
--
-- Observed on the first drained batches: "firecrawl: no usable bullets" and
-- "transformers: no usable bullets".
--
-- Only a deterministic failure counts. A rate limit or a network error is not
-- the row's fault, and burning its attempts for a Groq 429 would quietly
-- exclude tools that summarise perfectly well on a calmer day.
-- ============================================================================

alter table tools
  add column if not exists summary_attempts int not null default 0;

comment on column tools.summary_attempts is
  'Times the summariser produced nothing usable for this row. Transport and '
  'rate-limit failures are not counted. At 3 the row leaves the backlog.';

create or replace view tools_needing_summary as
  select id, name, tagline, description
  from tools
  where status in ('published', 'pending')
    and coalesce(jsonb_array_length(ai_summary), 0) = 0
    and coalesce(description, '') <> ''
    and summary_attempts < 3
  -- Newest first: a tool nobody has seen yet benefits more from a summary
  -- than one that has sat in the catalog for a month.
  order by created_at desc;

-- Summary coverage has to be measured against what can actually be
-- summarised, or a few hopeless rows leave the health panel permanently
-- warning about something nobody can fix.
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
  -- Rows still in reach of the summariser: has prose to work from, and has
  -- not been written off after repeated deterministic failures.
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

-- The summariser runs as the service role but writes through PostgREST, so the
-- increment goes through a function rather than a raw update: one statement,
-- and no chance of a bad payload rewriting the row it was counting.
create or replace function note_summary_attempt(tool_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update tools
     set summary_attempts = summary_attempts + 1
   where id = tool_id;
$$;

revoke all on function note_summary_attempt(uuid) from public, anon, authenticated;
