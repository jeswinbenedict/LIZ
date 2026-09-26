-- ============================================================================
-- Liz — what the scheduled jobs actually got back. Migration 0031.
--
-- 0024 noted the hole and worked around it: the jobs fire net.http_post and
-- return immediately, so cron records "succeeded" for the *SQL*, and a function
-- that 401s or 500s on every call still leaves a clean job log. Freshness
-- signals were the answer, and they are still the right first question.
--
-- But pg_net does keep the response, in net._http_response. Surfacing it turns
-- "the data stopped moving, work out why" into "the call came back 401". That
-- distinction took a round of guessing during the security work in 0029: the
-- first deploy of the service-role guard locked out cron as well as attackers,
-- and nothing in the job log said so.
-- ============================================================================

create or replace function recent_job_responses(limit_count int default 20)
returns table (
  responded_at timestamptz,
  status_code  int,
  ok           boolean,
  summary      text
)
language sql
stable
security definer
set search_path = public, net
as $$
  select
    r.created,
    r.status_code,
    r.status_code between 200 and 299,
    left(coalesce(r.error_msg, r.content), 200)
  from net._http_response r
  where is_moderator()
     or coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')
        = 'service_role'
  order by r.created desc
  limit greatest(limit_count, 1);
$$;

grant execute on function recent_job_responses(int) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- And make it a health signal, so nobody has to think to look.
--
-- Counts failed responses in the last six hours. The jobs run between four and
-- ninety-six times a day, so a handful of failures is a blip and a wall of them
-- is an outage — which is exactly the shape a broken credential produces.
-- ----------------------------------------------------------------------------
create or replace function failed_job_calls(window_length interval default '6 hours')
returns integer
language sql
stable
security definer
set search_path = public, net
as $$
  select count(*)::int
    from net._http_response r
   where r.created > now() - window_length
     and (r.status_code is null or r.status_code not between 200 and 299);
$$;

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
  select 'failed_job_calls_6h',
         case when failed_job_calls() > 20 then 'fail'
              when failed_job_calls() > 3  then 'warn'
              else 'ok' end,
         failed_job_calls()::numeric,
         'Scheduled calls that came back an error. Cron logs success either way.'
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
