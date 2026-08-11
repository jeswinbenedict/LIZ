-- ============================================================================
-- Liz — functions & triggers
-- Migration 0003: keep denormalized counts correct, auto-create profiles,
-- enforce the report auto-hide threshold, and compute trend / rising scores.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger trg_profiles_touch before update on profiles
  for each row execute function touch_updated_at();
create trigger trg_tools_touch before update on tools
  for each row execute function touch_updated_at();
create trigger trg_posts_touch before update on posts
  for each row execute function touch_updated_at();
create trigger trg_reviews_touch before update on reviews
  for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Auto-create a profile row when a new auth user signs up.
-- Username is derived from email and de-duplicated with a short suffix.
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  base_username text;
  final_username text;
begin
  base_username := lower(split_part(coalesce(new.email, 'user'), '@', 1));
  base_username := regexp_replace(base_username, '[^a-z0-9_]', '', 'g');
  if base_username = '' then base_username := 'user'; end if;
  final_username := base_username;
  while exists (select 1 from profiles where username = final_username) loop
    final_username := base_username || '_' || substr(gen_random_uuid()::text, 1, 4);
  end loop;

  insert into profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    final_username,
    coalesce(new.raw_user_meta_data->>'display_name', final_username),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- like_count on posts/reviews
-- ---------------------------------------------------------------------------
create or replace function sync_like_count()
returns trigger language plpgsql as $$
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

create trigger trg_likes_count
  after insert or delete on likes
  for each row execute function sync_like_count();

-- ---------------------------------------------------------------------------
-- comment_count on posts
-- ---------------------------------------------------------------------------
create or replace function sync_comment_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update posts set comment_count = comment_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update posts set comment_count = greatest(0, comment_count - 1) where id = old.post_id;
  end if;
  return null;
end $$;

create trigger trg_comments_count
  after insert or delete on comments
  for each row execute function sync_comment_count();

-- ---------------------------------------------------------------------------
-- avg_rating / rating_count on tools
-- ---------------------------------------------------------------------------
create or replace function sync_tool_rating()
returns trigger language plpgsql as $$
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

create trigger trg_reviews_rating
  after insert or update or delete on reviews
  for each row execute function sync_tool_rating();

-- ---------------------------------------------------------------------------
-- save_count on tools
-- ---------------------------------------------------------------------------
create or replace function sync_save_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update tools set save_count = save_count + 1 where id = new.tool_id;
  elsif (tg_op = 'DELETE') then
    update tools set save_count = greatest(0, save_count - 1) where id = old.tool_id;
  end if;
  return null;
end $$;

create trigger trg_bookmarks_count
  after insert or delete on bookmarks
  for each row execute function sync_save_count();

-- ---------------------------------------------------------------------------
-- Report auto-hide: once a piece of content is reported >= threshold times,
-- hide it and flag for admin review (§6.3, §13 "moderation from day one").
-- ---------------------------------------------------------------------------
create or replace function handle_report()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cnt int;
  threshold constant int := 3;
begin
  select count(*) into cnt from reports
    where target_type = new.target_type and target_id = new.target_id
      and status = 'open';

  if cnt >= threshold then
    if new.target_type = 'post' then
      update posts set status = 'hidden' where id = new.target_id;
    elsif new.target_type = 'comment' then
      update comments set status = 'hidden' where id = new.target_id;
    elsif new.target_type = 'review' then
      update reviews set status = 'hidden' where id = new.target_id;
    end if;
  end if;
  return null;
end $$;

create trigger trg_reports_autohide
  after insert on reports
  for each row execute function handle_report();

-- ---------------------------------------------------------------------------
-- Trend + rising scores (§7.1). Run on a schedule (pg_cron or n8n).
--   trend_score  = weighted recent engagement + velocity - age penalty
--   "Rising Early" = high velocity but still low absolute popularity, exposed
--   through the tools_rising view.
-- ---------------------------------------------------------------------------
create or replace function refresh_trend_scores()
returns void language plpgsql security definer set search_path = public as $$
begin
  update tools t set trend_score = sub.score
  from (
    select id,
      -- recent engagement
      (0.5 * view_count + 2.0 * save_count + 3.0 * rating_count)
      -- age penalty: newer tools keep more of their score
      * exp(-extract(epoch from (now() - created_at)) / (60*60*24*30.0))
      as score
    from tools
  ) sub
  where t.id = sub.id;
end $$;

-- "Rising Early" ranking: momentum high, absolute saves still low.
create or replace view tools_rising as
  select *,
    (trend_score + greatest(0, 20 - extract(day from (now() - created_at)))
       - ln(save_count + 10) * 6) as rising_score
  from tools
  where status = 'published'
  order by rising_score desc;
