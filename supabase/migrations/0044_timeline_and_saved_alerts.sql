-- ============================================================================
-- Liz — a tool's timeline, and alerts for saved tools. Migration 0044.
-- Safe to re-run.
--
-- 1. tool_changes: every change to a tool's price, as it happens. Liz already
--    noticed pricing changes to alert followers (0020, 0021) but kept no
--    record, so a tool page could not say "Free until 12 Oct, Freemium since".
--    History starts now; it cannot be back-filled.
-- 2. hn_posted_at: when the Show HN story went up, for the timeline.
-- 3. Saving a tool now means watching it. Save, Follow and Alerts were three
--    ideas where people expect one; change alerts now go to everyone who saved
--    the tool as well as everyone who followed it (existing follows keep
--    working), each person once.
-- ============================================================================

-- 1) Price history -----------------------------------------------------------
create table if not exists public.tool_changes (
  id         bigint generated always as identity primary key,
  tool_id    uuid not null references public.tools(id) on delete cascade,
  field      text not null check (field in ('pricing_type', 'price_note')),
  old_value  text,
  new_value  text,
  changed_at timestamptz not null default now()
);

create index if not exists idx_tool_changes_tool
  on public.tool_changes (tool_id, changed_at desc);

alter table public.tool_changes enable row level security;
drop policy if exists "read changes of published tools" on public.tool_changes;
create policy "read changes of published tools" on public.tool_changes
  for select using (
    exists (select 1 from public.tools t
             where t.id = tool_id and t.status = 'published')
  );

create or replace function public.record_tool_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- "unknown" to a price is the catalog catching up, not the product
  -- changing (same rule as the alerts, 0021).
  if new.pricing_type is distinct from old.pricing_type
     and coalesce(old.pricing_type::text, 'unknown') <> 'unknown' then
    insert into tool_changes (tool_id, field, old_value, new_value)
    values (new.id, 'pricing_type', old.pricing_type::text, new.pricing_type::text);
  end if;
  if new.price_note is distinct from old.price_note
     and coalesce(old.price_note, '') <> '' then
    insert into tool_changes (tool_id, field, old_value, new_value)
    values (new.id, 'price_note', old.price_note, new.price_note);
  end if;
  return new;
end $$;

drop trigger if exists trg_record_tool_change on public.tools;
create trigger trg_record_tool_change
  after update on public.tools
  for each row
  when (old.pricing_type is distinct from new.pricing_type
        or old.price_note is distinct from new.price_note)
  execute function public.record_tool_change();

-- 2) When the Show HN story went up ------------------------------------------
alter table public.tools add column if not exists hn_posted_at timestamptz;

create or replace function public.apply_signals(rows jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  updated int;
begin
  if jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array';
  end if;

  with incoming as (
    select (r ->> 'id')::uuid                   as id,
           nullif(r ->> 'gh_repo', '')          as gh_repo,
           (r ->> 'gh_stars')::int              as gh_stars,
           nullif(r ->> 'hn_id', '')            as hn_id,
           (r ->> 'hn_points')::int             as hn_points,
           (r ->> 'hn_comments')::int           as hn_comments,
           (r ->> 'hn_posted_at')::timestamptz  as hn_posted_at,
           r ? 'gh_stars'                       as has_stars,
           r ? 'hn_points'                      as has_points
      from jsonb_array_elements(rows) r
  )
  update tools t set
    gh_repo      = coalesce(i.gh_repo, t.gh_repo),
    gh_stars     = case when i.has_stars  then i.gh_stars    else t.gh_stars    end,
    hn_id        = coalesce(i.hn_id, t.hn_id),
    hn_points    = case when i.has_points then i.hn_points   else t.hn_points   end,
    hn_comments  = case when i.has_points then i.hn_comments else t.hn_comments end,
    hn_posted_at = coalesce(i.hn_posted_at, t.hn_posted_at),
    signals_at   = now()
  from incoming i
  where i.id = t.id;

  get diagnostics updated = row_count;

  perform snapshot_signals();
  perform refresh_trend_scores();
  return updated;
end $$;

revoke all on function public.apply_signals(jsonb) from public, anon, authenticated;

-- 3) Alerts for everyone watching: followers and savers ----------------------
create or replace function public.on_tool_change_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  watcher   record;
  title     text;
  body      text;
  ntype     text;
begin
  if new.status is distinct from 'published'::publish_status then
    return new;
  end if;

  if new.pricing_type is distinct from old.pricing_type
     and old.pricing_type is not null
     and new.pricing_type is not null
     and old.pricing_type <> 'unknown'::pricing_type
     and new.pricing_type <> 'unknown'::pricing_type then
    ntype := 'pricing';
    title := new.name || ' changed its pricing';
    body  := initcap(old.pricing_type::text) || ' is now '
             || initcap(new.pricing_type::text) || '.';
  elsif new.trend_rank is not null
        and new.trend_rank <= 10
        and (old.trend_rank is null or old.trend_rank > 10) then
    ntype := 'trending';
    title := new.name || ' is rising';
    body  := coalesce(new.trend_reason || '. ', '')
             || 'It just entered the top 10 on Liz.';
  else
    return new;
  end if;

  for watcher in
    select follower_id as user_id
      from public.follows
     where target_type = 'tool' and target_id = new.id
    union
    select user_id
      from public.bookmarks
     where tool_id = new.id
  loop
    perform public.notify_user(
      watcher.user_id,
      ntype,
      title,
      body,
      '/tools/' || new.slug,
      jsonb_build_object('tool_id', new.id)
    );
  end loop;

  return new;
end $$;
