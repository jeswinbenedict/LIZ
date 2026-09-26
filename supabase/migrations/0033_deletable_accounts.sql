-- ============================================================================
-- Liz — let people actually delete their account. Migration 0033.
--
-- Found by running the delete flow end to end for the first time. A brand new
-- account deletes fine. An account that has bookmarked a single tool does not:
--
--   {"data":null,"error":"Database error deleting user"}
--
-- Not a missing cascade — every foreign key already has ON DELETE CASCADE, and
-- deleting the bookmark by hand and then the user works. The cascade itself is
-- what fails.
--
-- Deleting an auth user runs as `supabase_auth_admin`. The cascade reaches
-- `bookmarks`, which fires `sync_save_count`, which updates `public.tools` —
-- and that role has no rights in the public schema. The trigger functions were
-- written without `security definer`, so they run as whoever caused the delete
-- rather than as their owner, and the whole transaction rolls back.
--
-- So: anyone who had bookmarked a tool, liked a post, written a review or left
-- a comment could not delete their account. That is a GDPR obligation and an
-- App Store requirement, failing silently behind a generic error.
--
-- These four only ever adjust a counter on a row the trigger itself names, and
-- run no caller-supplied SQL, so definer rights give them nothing they could
-- be talked into misusing. search_path is pinned regardless, because a definer
-- function that resolves names through the caller's path is the actual risk.
-- ============================================================================

create or replace function sync_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t text;
  tid uuid;
  delta int;
begin
  if (tg_op = 'INSERT') then
    t := new.target_type; tid := new.target_id; delta := 1;
  else
    t := old.target_type; tid := old.target_id; delta := -1;
  end if;

  if t = 'post' then
    update posts set like_count = greatest(0, like_count + delta) where id = tid;
  elsif t = 'review' then
    update reviews set like_count = greatest(0, like_count + delta) where id = tid;
  end if;
  return null;
end $$;

create or replace function sync_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update posts set comment_count = comment_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update posts set comment_count = greatest(0, comment_count - 1)
     where id = old.post_id;
  end if;
  return null;
end $$;

create or replace function sync_tool_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  tid uuid := coalesce(new.tool_id, old.tool_id);
begin
  update tools t set
    avg_rating = coalesce((
      select round(avg(rating)::numeric, 2) from reviews
      where tool_id = tid and status = 'active'), 0),
    rating_count = (
      select count(*) from reviews
      where tool_id = tid and status = 'active')
  where t.id = tid;
  return null;
end $$;

create or replace function sync_save_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update tools set save_count = save_count + 1 where id = new.tool_id;
  elsif (tg_op = 'DELETE') then
    update tools set save_count = greatest(0, save_count - 1)
     where id = old.tool_id;
  end if;
  return null;
end $$;

-- handle_report() was already written with definer rights, so a cascade
-- reaching `reports` is fine and it is left alone.
