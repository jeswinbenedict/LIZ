-- ============================================================================
-- Liz — activity notifications (in-app now; FCM push when configured).
-- Migration 0007. Safe to re-run.
--
-- Design: every event records an in-app `notifications` row (works with ZERO
-- external config), and *additionally* fans out a push via the send-notification
-- Edge Function **only if** push settings are present. So this migration is
-- fully functional the moment it's applied, and "lights up" push once you set
-- the two settings below.
-- ============================================================================

create extension if not exists pg_net;

-- Stream notifications to connected clients (live inbox / unread badge).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- Central helper: record an in-app notification and (when configured) push it.
-- ----------------------------------------------------------------------------
create or replace function public.notify_user(
  target_user uuid,
  ntype       text,
  title       text,
  body        text,
  route       text default null,
  extra       jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url  text := current_setting('app.functions_url', true);
  fn_key  text := current_setting('app.service_role_key', true);
begin
  -- 1) Always record the in-app notification.
  insert into public.notifications (user_id, type, payload)
  values (
    target_user,
    ntype,
    jsonb_build_object('title', title, 'body', body, 'route', route)
      || coalesce(extra, '{}'::jsonb)
  );

  -- 2) Best-effort push. No-op unless BOTH settings are present (see footer).
  if fn_url is not null and fn_url <> '' and fn_key is not null and fn_key <> '' then
    perform net.http_post(
      url     := fn_url || '/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || fn_key
      ),
      body    := jsonb_build_object(
        'user_id', target_user,
        'title',   title,
        'body',    body,
        'route',   route,
        'data',    extra
      )
    );
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- Trigger: a reply to your post.
-- ----------------------------------------------------------------------------
create or replace function public.on_comment_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  who      text;
begin
  select user_id into owner_id from public.posts where id = new.post_id;
  if owner_id is null or owner_id = new.user_id then
    return new; -- deleted post, or you commented on your own post
  end if;

  select coalesce(nullif(display_name, ''), 'Someone')
    into who from public.profiles where id = new.user_id;

  perform public.notify_user(
    owner_id,
    'comment',
    'New reply to your post',
    who || ' replied: ' || left(new.body, 80),
    '/post/' || new.post_id::text,
    jsonb_build_object('post_id', new.post_id, 'actor_id', new.user_id)
  );
  return new;
end $$;

drop trigger if exists trg_comment_notify on public.comments;
create trigger trg_comment_notify
  after insert on public.comments
  for each row execute function public.on_comment_notify();

-- ----------------------------------------------------------------------------
-- Trigger: someone followed you.
-- ----------------------------------------------------------------------------
create or replace function public.on_follow_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  who text;
begin
  if new.target_type <> 'user' or new.target_id = new.follower_id then
    return new;
  end if;

  select coalesce(nullif(display_name, ''), 'Someone')
    into who from public.profiles where id = new.follower_id;

  perform public.notify_user(
    new.target_id,
    'follow',
    'New follower',
    who || ' started following you',
    '/user/' || new.follower_id::text,
    jsonb_build_object('actor_id', new.follower_id)
  );
  return new;
end $$;

drop trigger if exists trg_follow_notify on public.follows;
create trigger trg_follow_notify
  after insert on public.follows
  for each row execute function public.on_follow_notify();

-- ============================================================================
-- To ENABLE PUSH (after deploying the send-notification function and setting up
-- Firebase — see docs/FCM_SETUP.md), point the DB at your functions endpoint:
--
--   alter database postgres set app.functions_url    = 'https://<PROJECT_REF>.functions.supabase.co';
--   alter database postgres set app.service_role_key = '<SERVICE_ROLE_KEY>';
--
-- Until then, only in-app notifications are written (no push) — by design.
-- Prefer Supabase Vault over inline keys for production.
-- ============================================================================
