-- Columns a signed-in person must not be able to change about their own rows.
--
-- Found 5 October 2026: "update own profile" let a signed-in person update
-- every column of their profile, role included — one request,
--   PATCH /rest/v1/profiles?id=eq.<me>  {"role": "admin"}
-- and they were an admin, with the moderation console, the error reports and
-- every moderator power. Anyone can get there: signing up with Firebase is
-- open. The same policies let an author put back a review, post or comment a
-- moderator had hidden, or set its like count.
--
-- Column privileges cannot fix this: moderators hide content through the same
-- `authenticated` role, so `status` must stay writable for them. A trigger
-- can tell them apart. It applies only to statements run directly as `anon`
-- or `authenticated` — the API — so the counter triggers (sync_like_count and
-- the like, SECURITY DEFINER, running as the owner), the service role, cron
-- and migrations are untouched.

create or replace function public.guard_profile_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  -- Only an admin hands out roles; a moderator cannot make another.
  if new.role is distinct from old.role and not exists (
    select 1 from profiles where id = current_uid() and role = 'admin'
  ) then
    new.role := old.role;
  end if;
  return new;
end $$;

drop trigger if exists trg_profiles_guard on public.profiles;
create trigger trg_profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_columns();

-- Reviews, posts and comments: what an author may change is what they wrote.
create or replace function public.guard_content_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  new.id := old.id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  if tg_table_name in ('reviews', 'posts') then
    new.tool_id := old.tool_id;
    new.like_count := old.like_count;
  end if;
  if tg_table_name = 'posts' then
    new.comment_count := old.comment_count;
  end if;
  if tg_table_name = 'comments' then
    new.post_id := old.post_id;
  end if;
  -- Hiding and restoring is moderation.
  if new.status is distinct from old.status and not is_moderator() then
    new.status := old.status;
  end if;
  return new;
end $$;

drop trigger if exists trg_reviews_guard on public.reviews;
create trigger trg_reviews_guard
  before update on public.reviews
  for each row execute function public.guard_content_columns();

drop trigger if exists trg_posts_guard on public.posts;
create trigger trg_posts_guard
  before update on public.posts
  for each row execute function public.guard_content_columns();

drop trigger if exists trg_comments_guard on public.comments;
create trigger trg_comments_guard
  before update on public.comments
  for each row execute function public.guard_content_columns();

revoke all on function public.guard_profile_columns() from public, anon, authenticated;
revoke all on function public.guard_content_columns() from public, anon, authenticated;
