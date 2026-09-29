-- ============================================================================
-- Liz — honest signals. Migration 0037. Safe to re-run.
--
-- Until now the numbers behind the ranking were not measurements. The curated
-- tools carried ratings and view counts typed into a seed file (ChatGPT
-- "982,000 views", Claude "4.8 from 18,400 ratings") while the reviews table
-- was empty; GitHub rows stored their star count in view_count; and nothing
-- in the app ever recorded a view. "Rising this week" therefore ranked the
-- most famous tools by invented totals, with no time window at all.
--
-- This migration:
--   1. keeps the seeded figures in a private backup, then clears them, once;
--   2. gives outside signals their own columns (GitHub stars, Hacker News
--      points), filled by `python -m liz_scraper signals`;
--   3. records what people actually do in `events`, through track();
--   4. snapshots every published tool's signals daily, so change over time
--      can be measured at all — history cannot be collected after the fact;
--   5. ranks by momentum over the last seven days, and says why in words.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Outside signals and the ranking's output
-- ---------------------------------------------------------------------------
alter table public.tools
  add column if not exists gh_repo      text,
  add column if not exists gh_stars     int,
  add column if not exists hn_id        text,
  add column if not exists hn_points    int,
  add column if not exists hn_comments  int,
  add column if not exists signals_at   timestamptz,
  add column if not exists click_count  int not null default 0,
  add column if not exists momentum     numeric not null default 0,
  add column if not exists trend_reason text;

comment on column public.tools.view_count is
  'Tool page views recorded by track(), one per visitor per 30 minutes.';
comment on column public.tools.click_count is
  'Visits to the tool''s website from Liz, recorded by track().';
comment on column public.tools.momentum is
  'Growth over the last seven days across GitHub, Hacker News and Liz. See refresh_trend_scores().';
comment on column public.tools.trend_reason is
  'The biggest contributor to momentum, in words — shown instead of a bare score.';

create index if not exists idx_tools_momentum
  on public.tools (momentum desc, created_at desc) where status = 'published';
create index if not exists idx_tools_created_published
  on public.tools (created_at desc) where status = 'published';

-- ---------------------------------------------------------------------------
-- 1) Back up and clear the seeded figures — exactly once
-- ---------------------------------------------------------------------------
-- The guard is the backup table itself: a second run finds it and leaves the
-- real counts that have accumulated since alone.
do $$
begin
  if to_regclass('public.seeded_metrics_backup') is null then
    create table public.seeded_metrics_backup (
      tool_id      uuid primary key,
      view_count   int,
      save_count   int,
      avg_rating   numeric,
      rating_count int,
      backed_up_at timestamptz not null default now()
    );
    comment on table public.seeded_metrics_backup is
      'Figures that were typed into seed files rather than measured, kept for '
      'reference when they were cleared by migration 0037. Never shown.';
    alter table public.seeded_metrics_backup enable row level security;

    insert into public.seeded_metrics_backup
      (tool_id, view_count, save_count, avg_rating, rating_count)
    select id, view_count, save_count, avg_rating, rating_count
      from public.tools
     where view_count > 0 or save_count > 0 or rating_count > 0;

    -- GitHub rows kept their star count in view_count. It is a real number,
    -- just in the wrong place.
    update public.tools
       set gh_stars = view_count
     where source = 'github' and gh_stars is null;

    update public.tools set view_count = 0 where view_count <> 0;

    -- Ratings and saves from the rows that actually exist.
    update public.tools t set
      avg_rating = coalesce((
        select round(avg(r.rating)::numeric, 2) from public.reviews r
         where r.tool_id = t.id and r.status = 'active'), 0),
      rating_count = (
        select count(*) from public.reviews r
         where r.tool_id = t.id and r.status = 'active'),
      save_count = (
        select count(*) from public.bookmarks b where b.tool_id = t.id);
  end if;
end $$;

update public.tools
   set gh_repo = substring(source_url from '^https://github\.com/([^/]+/[^/#?]+)')
 where source = 'github' and gh_repo is null;

-- ---------------------------------------------------------------------------
-- 2) What people do — append-only, written only through track()
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id         bigint generated always as identity primary key,
  name       text        not null,
  -- A random id the browser keeps. No IP address or fingerprint is stored.
  anon_id    uuid        not null,
  user_id    uuid        references public.profiles(id) on delete set null,
  tool_id    uuid        references public.tools(id) on delete cascade,
  path       text,
  props      jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.events is
  'First-party usage events: page and tool views, website visits, saves, '
  'searches. Written only through track(); readable only by admins through '
  'usage_summary(). Deleting an account detaches its events from it.';

create index if not exists idx_events_created on public.events (created_at);
create index if not exists idx_events_name_created on public.events (name, created_at);
create index if not exists idx_events_tool
  on public.events (tool_id, name, created_at) where tool_id is not null;
create index if not exists idx_events_anon on public.events (anon_id, created_at);

alter table public.events enable row level security;
-- No policies on purpose: no client reads or writes this table directly.

create or replace function public.track(
  p_name  text,
  p_anon  uuid,
  p_tool  uuid  default null,
  p_path  text  default null,
  p_props jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller text;
begin
  if p_anon is null or p_name is null or p_name not in (
    'page_view', 'tool_view', 'outbound_click', 'save', 'unsave',
    'search', 'ask', 'compare', 'share', 'sign_up', 'sign_in'
  ) then
    return;
  end if;

  if p_props is null or jsonb_typeof(p_props) <> 'object'
     or length(p_props::text) > 1000 then
    p_props := '{}'::jsonb;
  end if;
  p_path := left(p_path, 200);

  -- A ceiling per address, so one script cannot flood the table. The address
  -- is used for the count and never stored.
  caller := nullif(trim(split_part(coalesce(
    nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''),
    ',', 1)), '');
  if not take_rate_limit('track:' || coalesce(caller, p_anon::text), 600) then
    return;
  end if;

  if p_name in ('tool_view', 'outbound_click', 'save', 'unsave') then
    if p_tool is null or not exists (
      select 1 from tools where id = p_tool and status = 'published'
    ) then
      return;
    end if;
  end if;

  -- One view and one website visit per visitor per tool per half hour; one
  -- save per visitor per tool, ever. Reloading a page is not interest.
  if p_name in ('tool_view', 'outbound_click') and exists (
    select 1 from events
     where anon_id = p_anon and tool_id = p_tool and name = p_name
       and created_at > now() - interval '30 minutes'
  ) then
    return;
  end if;
  if p_name = 'save' and exists (
    select 1 from events
     where anon_id = p_anon and tool_id = p_tool and name = 'save'
  ) then
    return;
  end if;

  insert into events (name, anon_id, user_id, tool_id, path, props)
  values (p_name, p_anon, auth.uid(), p_tool, p_path, p_props);
end $$;

revoke all on function public.track(text, uuid, uuid, text, jsonb) from public;
grant execute on function public.track(text, uuid, uuid, text, jsonb)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Daily history
-- ---------------------------------------------------------------------------
create table if not exists public.tool_signal_snapshots (
  tool_id     uuid not null references public.tools(id) on delete cascade,
  day         date not null,
  gh_stars    int,
  hn_points   int,
  hn_comments int,
  -- Cumulative totals at the time of the snapshot; growth is the difference
  -- between two days.
  views       int  not null default 0,
  clicks      int  not null default 0,
  saves       int  not null default 0,
  primary key (tool_id, day)
);

comment on table public.tool_signal_snapshots is
  'One row per published tool per day: outside signals and cumulative Liz '
  'activity. The only source of "change over time" — it cannot be back-filled.';

create index if not exists idx_snapshots_day on public.tool_signal_snapshots (day);

alter table public.tool_signal_snapshots enable row level security;
drop policy if exists "read snapshots of published tools" on public.tool_signal_snapshots;
create policy "read snapshots of published tools" on public.tool_signal_snapshots
  for select using (
    exists (select 1 from public.tools t
             where t.id = tool_id and t.status = 'published')
  );

create or replace function public.snapshot_signals()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  written int;
begin
  -- Totals from the event log. Kept on tools too, so a page can show them
  -- without a join. Only rows whose totals moved are written.
  with totals as (
    select tool_id,
           count(*) filter (where name = 'tool_view')      as views,
           count(*) filter (where name = 'outbound_click') as clicks
      from events
     where tool_id is not null
     group by tool_id
  )
  update tools t
     set view_count = x.views, click_count = x.clicks
    from totals x
   where x.tool_id = t.id
     and (t.view_count, t.click_count) is distinct from (x.views, x.clicks);

  insert into tool_signal_snapshots
    (tool_id, day, gh_stars, hn_points, hn_comments, views, clicks, saves)
  select t.id, current_date, t.gh_stars, t.hn_points, t.hn_comments,
         t.view_count, t.click_count,
         greatest(t.save_count, coalesce(s.saves, 0))
    from tools t
    left join (
      select tool_id, count(distinct anon_id)::int as saves
        from events where name = 'save' and tool_id is not null
       group by tool_id
    ) s on s.tool_id = t.id
   where t.status = 'published'
  on conflict (tool_id, day) do update set
    gh_stars    = excluded.gh_stars,
    hn_points   = excluded.hn_points,
    hn_comments = excluded.hn_comments,
    views       = excluded.views,
    clicks      = excluded.clicks,
    saves       = excluded.saves;

  get diagnostics written = row_count;
  return written;
end $$;

revoke all on function public.snapshot_signals() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Momentum
-- ---------------------------------------------------------------------------
-- Compact numbers for the reason text: 1234 -> 1.2k.
create or replace function public.compact_count(n numeric)
returns text
language sql
immutable
as $$
  select case
    when n >= 1000000 then trim(to_char(round(n / 1000000.0, 1), 'FM999990.0')) || 'M'
    when n >= 10000   then round(n / 1000.0)::text || 'k'
    when n >= 1000    then trim(to_char(round(n / 1000.0, 1), 'FM990.0')) || 'k'
    else round(n)::text
  end;
$$;

create or replace function public.refresh_trend_scores()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with latest as (
    select distinct on (tool_id) *
      from tool_signal_snapshots
     where day >= current_date - 1
     order by tool_id, day desc
  ),
  -- The oldest snapshot inside the week, as long as it is older than the
  -- latest one. No such row means there is no history yet, and no growth to
  -- claim.
  base as (
    select distinct on (s.tool_id) s.*
      from tool_signal_snapshots s
      join latest l on l.tool_id = s.tool_id and s.day < l.day
     where s.day >= current_date - 7
     order by s.tool_id, s.day asc
  ),
  parts as (
    select t.id,
           -- First seen by Liz this week: points earned at launch happened
           -- this week too, so they count in full.
           (t.created_at > now() - interval '7 days') as fresh,
           greatest(coalesce(l.gh_stars, 0) - coalesce(b.gh_stars, l.gh_stars, 0), 0) as d_stars,
           coalesce(b.gh_stars, l.gh_stars, 0) as base_stars,
           case when t.created_at > now() - interval '7 days'
                then coalesce(t.hn_points, 0)
                else greatest(coalesce(l.hn_points, 0) - coalesce(b.hn_points, l.hn_points, 0), 0)
           end as d_points,
           case when b.tool_id is null and t.created_at > now() - interval '7 days'
                then coalesce(l.saves, 0)
                else greatest(coalesce(l.saves, 0) - coalesce(b.saves, l.saves, 0), 0) end as d_saves,
           case when b.tool_id is null and t.created_at > now() - interval '7 days'
                then coalesce(l.clicks, 0)
                else greatest(coalesce(l.clicks, 0) - coalesce(b.clicks, l.clicks, 0), 0) end as d_clicks,
           case when b.tool_id is null and t.created_at > now() - interval '7 days'
                then coalesce(l.views, 0)
                else greatest(coalesce(l.views, 0) - coalesce(b.views, l.views, 0), 0) end as d_views
      from tools t
      left join latest l on l.tool_id = t.id
      left join base   b on b.tool_id = t.id
     where t.status = 'published'
  ),
  terms as (
    select id, fresh, d_stars, d_points, d_saves, d_clicks, d_views,
           -- Absolute gain plus gain relative to size: 500 new stars mean
           -- more on a 1k repo than on a 100k one.
           ln(1 + d_stars) + ln(1 + 100.0 * d_stars / (base_stars + 1000)) as star_term,
           ln(1 + d_points)                                                  as hn_term,
           1.2 * ln(1 + 3 * d_saves + d_clicks + 0.3 * d_views)              as liz_term
      from parts
  ),
  scored as (
    select id,
           star_term + hn_term + liz_term as m,
           case
             when star_term + hn_term + liz_term = 0 then null
             when star_term >= hn_term and star_term >= liz_term then
               '+' || compact_count(d_stars) || ' GitHub stars this week'
             when hn_term >= liz_term then
               case when fresh
                    then compact_count(d_points) || ' points on Hacker News'
                    else '+' || compact_count(d_points) || ' Hacker News points this week'
               end
             when d_saves > 0 then
               '+' || compact_count(d_saves) || case when d_saves = 1 then ' save' else ' saves' end || ' on Liz this week'
             when d_clicks > 0 then
               compact_count(d_clicks) || case when d_clicks = 1 then ' visit' else ' visits' end || ' from Liz this week'
             else
               compact_count(d_views) || case when d_views = 1 then ' view' else ' views' end || ' on Liz this week'
           end as reason
      from terms
  )
  update tools t
     set momentum     = round(s.m::numeric, 4),
         trend_reason = s.reason
    from scored s
   where s.id = t.id
     and (t.momentum, t.trend_reason) is distinct from (round(s.m::numeric, 4), s.reason);

  -- 0-100 as a percentile of momentum, so the scale means "faster than N% of
  -- the catalog" rather than a number nobody can interpret. No momentum, 0.
  with ranked as (
    select id,
           case when momentum > 0
                then round(100 * percent_rank() over (order by momentum))
                else 0 end as score,
           row_number() over (order by momentum desc, created_at desc, id) as rn
      from tools
     where status = 'published'
  )
  update tools t
     set trend_score = r.score, trend_rank = r.rn
    from ranked r
   where r.id = t.id
     and (t.trend_score, t.trend_rank) is distinct from (r.score, r.rn);

  update tools set trend_rank = null, momentum = 0, trend_reason = null
   where status <> 'published'
     and (trend_rank is not null or momentum <> 0 or trend_reason is not null);
end $$;

revoke all on function public.refresh_trend_scores() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Usage for the admin console
-- ---------------------------------------------------------------------------
create or replace function public.usage_summary(days int default 7)
returns table (metric text, value bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_moderator() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    with recent as (
      select * from events
       where created_at > now() - make_interval(days => greatest(days, 1))
    )
    select 'visitors', count(distinct anon_id) from recent
    union all select 'page_views', count(*) filter (where name = 'page_view') from recent
    union all select 'tool_views', count(*) filter (where name = 'tool_view') from recent
    union all select 'website_visits', count(*) filter (where name = 'outbound_click') from recent
    union all select 'saves', count(*) filter (where name = 'save') from recent
    union all select 'searches', count(*) filter (where name in ('search', 'ask')) from recent
    union all select 'sign_ups', count(*) filter (where name = 'sign_up') from recent
    union all select 'visitors_who_saved',
      count(distinct anon_id) filter (where name = 'save') from recent
    union all select 'returning_visitors', (
      select count(*) from (
        select anon_id from recent
         group by anon_id
        having count(distinct created_at::date) > 1) r);
end $$;

revoke all on function public.usage_summary(int) from public, anon;
grant execute on function public.usage_summary(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Health: is the history actually being written?
-- ---------------------------------------------------------------------------
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
  ),
  newest_snapshot as (
    select (current_date - max(day)) * 24 as hours from tool_signal_snapshots
  ),
  outside_signals as (
    select extract(epoch from now() - max(signals_at)) / 3600 as hours from tools
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
    from open_reports
  union all
  select 'signal_history_hours',
         case when hours is null then 'fail'
              when hours > 48 then 'fail'
              when hours > 24 then 'warn'
              else 'ok' end,
         coalesce(hours, -1)::numeric,
         'Hours since the last daily snapshot. A missed day is history lost for good.'
    from newest_snapshot
  union all
  select 'outside_signals_hours',
         case when hours is null then 'warn'
              when hours > 72 then 'fail'
              when hours > 36 then 'warn'
              else 'ok' end,
         round(coalesce(hours, -1)::numeric, 1),
         'Hours since GitHub stars and Hacker News points were last read.'
    from outside_signals;
$$;

grant execute on function system_health() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Schedule: snapshot, then rank. Replaces the old ranking-only job.
-- ---------------------------------------------------------------------------
select cron.unschedule('refresh-trend-scores-daily')
 where exists (select 1 from cron.job where jobname = 'refresh-trend-scores-daily');

select cron.schedule(
  'snapshot-and-rank-daily',
  '50 4 * * *', -- after fetch-tools (04:15) has refreshed GitHub rows
  $$ select public.snapshot_signals(); select public.refresh_trend_scores(); $$
);

select public.snapshot_signals();
select public.refresh_trend_scores();
