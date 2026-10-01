-- ============================================================================
-- Liz — real-user speed and retention. Migration 0051. Safe to re-run.
--
-- Two numbers the usage panel could not show: how fast the first screen
-- actually draws for real visitors (Lighthouse only ever measured a lab
-- browser), and whether people come back.
--
--   * track() accepts a 'perf' event: the app reports, once per page load,
--     how many milliseconds after navigation its first frame drew.
--   * usage_summary() adds the median and slowest-tenth first frame, and
--     week-over-week returning visitors (visited last week and this week).
-- ============================================================================

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
    'search', 'ask', 'compare', 'share', 'sign_up', 'sign_in', 'perf'
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
    ),
    frames as (
      select (props ->> 'first_frame_ms')::numeric as ms
        from recent
       where name = 'perf' and props ? 'first_frame_ms'
    ),
    this_week as (
      select distinct anon_id from events
       where created_at > now() - interval '7 days'
    ),
    last_week as (
      select distinct anon_id from events
       where created_at between now() - interval '14 days' and now() - interval '7 days'
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
        having count(distinct created_at::date) > 1) r)
    union all select 'came_back_this_week', (
      select count(*) from last_week l join this_week t using (anon_id))
    union all select 'visitors_last_week', (select count(*) from last_week)
    union all select 'first_frame_ms_median', (
      select round(percentile_cont(0.5) within group (order by ms))::bigint from frames)
    union all select 'first_frame_ms_p90', (
      select round(percentile_cont(0.9) within group (order by ms))::bigint from frames);
end $$;

revoke all on function public.usage_summary(int) from public, anon;
grant execute on function public.usage_summary(int) to authenticated;
