-- ============================================================================
-- Liz — knowing when something has quietly stopped. Migration 0024.
--
-- Everything that keeps Liz current runs on a schedule nobody watches: the
-- nightly GitHub fetch, the news pull, the ranking refresh, the embedding and
-- summary backfills. pg_cron records whether the *SQL* it ran succeeded, but
-- each of those jobs works by firing net.http_post at an Edge Function and
-- returning immediately — so a function that 500s on every call still leaves a
-- row saying the cron run succeeded.
--
-- The only honest signal is the data itself. If the catalog has not gained a
-- tool in three days, something upstream is broken, whatever the job log says.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- system_health — one row per signal, with a verdict.
--
-- Thresholds are set from what these jobs actually do: tools are fetched daily
-- and the feed is small enough that a quiet day is normal, so tools go stale at
-- three days; news is pulled hourly and a full day of silence is not normal.
-- ----------------------------------------------------------------------------
create or replace function system_health()
returns table (
  signal      text,
  status      text,   -- 'ok' | 'warn' | 'fail'
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
  summarised as (
    select count(*)::numeric as n from tools
     where status = 'published'
       and ai_summary is not null
       and jsonb_array_length(
             case when jsonb_typeof(ai_summary) = 'array'
                  then ai_summary else '[]'::jsonb end
           ) > 0
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
  -- Ask Liz and "similar tools" both go quiet for anything unembedded, and
  -- they go quiet without erroring, which is exactly the kind of failure that
  -- never gets reported.
  select 'embedding_coverage_pct',
         case when p.n = 0 then 'fail'
              when e.n / p.n < 0.90 then 'warn'
              when e.n / p.n < 0.50 then 'fail'
              else 'ok' end,
         round(case when p.n = 0 then 0 else 100 * e.n / p.n end, 1),
         'Published tools carrying a search embedding.'
    from published p, embedded e
  union all
  select 'ai_summary_coverage_pct',
         case when p.n = 0 then 'fail'
              when s.n / p.n < 0.75 then 'warn'
              else 'ok' end,
         round(case when p.n = 0 then 0 else 100 * s.n / p.n end, 1),
         'Published tools with an AI summary on their page.'
    from published p, summarised s
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

-- ----------------------------------------------------------------------------
-- Did the scheduled jobs even run?
--
-- Freshness says whether the work landed; this says whether the attempt was
-- made. Both are needed to tell "the job is broken" from "there was nothing
-- new to fetch". cron.job_run_details is not reachable over the REST API, so
-- it is surfaced here, moderator-only.
-- ----------------------------------------------------------------------------
create or replace function recent_job_runs(limit_count int default 20)
returns table (
  job_name   text,
  status     text,
  started_at timestamptz,
  duration_s numeric,
  message    text
)
language sql
stable
security definer
set search_path = public, cron
as $$
  select
    j.jobname::text,
    d.status::text,
    d.start_time,
    round(extract(epoch from (d.end_time - d.start_time))::numeric, 2),
    left(coalesce(d.return_message, ''), 200)
  from cron.job_run_details d
  join cron.job j on j.jobid = d.jobid
  where is_moderator()
  order by d.start_time desc
  limit greatest(limit_count, 1);
$$;

grant execute on function recent_job_runs(int) to authenticated;

-- ----------------------------------------------------------------------------
-- The alert itself.
--
-- A dashboard nobody opens is not monitoring. This runs on its own schedule,
-- and when a signal fails it notifies every admin through the same path the
-- app already uses for tool alerts — in-app immediately, and push wherever a
-- device is registered.
--
-- Only 'fail' notifies. A warning is for someone looking at the panel; waking
-- people for warnings is how alerts get muted.
-- ----------------------------------------------------------------------------
create or replace function check_system_health()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  failing  record;
  admin    record;
  summary  text := '';
  failures int  := 0;
begin
  for failing in
    select signal, value, detail from system_health() where status = 'fail'
  loop
    failures := failures + 1;
    summary := summary || failing.signal || ' = ' || failing.value || '. ';
  end loop;

  if failures = 0 then
    return;
  end if;

  -- One notification listing everything wrong, not one per signal: when
  -- ingestion stops, several signals fail together and they are one incident.
  for admin in select id from profiles where role = 'admin' loop
    perform public.notify_user(
      admin.id,
      'health',
      'Liz needs attention',
      left(summary, 300),
      '/admin',
      jsonb_build_object('failures', failures)
    );
  end loop;
end $$;

-- Hourly, on the half hour, so it never lands on top of the jobs it watches.
select cron.schedule(
  'check-system-health-hourly',
  '30 * * * *',
  $$ select public.check_system_health(); $$
);
