-- ============================================================================
-- Liz — private preferences. Migration 0050. Safe to re-run.
--
-- Two things a person tells Liz about themselves: which kinds of tools they
-- care about (Discover's "For you" shelf) and which changes they want to hear
-- about. Neither belongs on `profiles`, which anyone can read; this table is
-- readable and writable only by its owner.
--
-- Alerts (0044) now respect the choices: a saved tool's price change or rise
-- reaches only the people who still want that kind of alert.
-- ============================================================================

create table if not exists public.user_preferences (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  interests   text[] not null default '{}',
  alert_prefs jsonb  not null default '{"pricing": true, "trending": true}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

drop policy if exists "own preferences: read" on public.user_preferences;
create policy "own preferences: read" on public.user_preferences
  for select using (user_id = auth.uid());
drop policy if exists "own preferences: insert" on public.user_preferences;
create policy "own preferences: insert" on public.user_preferences
  for insert with check (user_id = auth.uid());
drop policy if exists "own preferences: update" on public.user_preferences;
create policy "own preferences: update" on public.user_preferences
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Whether a person wants alerts of this type. No row means the defaults: yes.
create or replace function public.wants_alert(uid uuid, alert_type text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (alert_prefs ->> alert_type)::boolean
       from user_preferences where user_id = uid),
    true);
$$;

revoke all on function public.wants_alert(uuid, text) from public, anon, authenticated;

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
    continue when not wants_alert(watcher.user_id, ntype);
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
