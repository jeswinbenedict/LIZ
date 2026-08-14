-- Liz — ONE-PASTE SETUP (generated from migrations/ + seed). Safe to re-run.

-- ===== migrations/0001_schema.sql =====
-- ============================================================================
-- Liz — core schema (Postgres / Supabase)
-- Migration 0001: tables, types, indexes.
-- All tables use uuid PKs and created_at/updated_at. RLS is enabled here and
-- policies are defined in 0002_rls.sql. Counts are denormalized and kept in
-- sync by triggers in 0003_functions.sql.
-- ============================================================================

create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "pg_trgm";        -- fast ILIKE / fuzzy search

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('user', 'moderator', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type pricing_type as enum ('free', 'freemium', 'paid', 'unknown');
exception when duplicate_object then null; end $$;

do $$ begin
  create type publish_status as enum ('pending', 'published', 'hidden');
exception when duplicate_object then null; end $$;

do $$ begin
  create type content_status as enum ('active', 'hidden', 'removed');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- profiles  (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text not null default '',
  avatar_url   text,
  bio          text,
  role         user_role not null default 'user',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------
create table if not exists categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text unique not null,
  icon       text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- tools  (apps / AI tools / products)
-- ---------------------------------------------------------------------------
create table if not exists tools (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text unique not null,
  tagline       text not null default '',
  description   text not null default '',
  ai_summary    jsonb not null default '[]'::jsonb,   -- array of bullet strings
  website_url   text,
  logo_url      text,
  category      text references categories(slug) on update cascade,
  tags          text[] not null default '{}',
  platforms     text[] not null default '{}',
  pricing_type  pricing_type not null default 'unknown',
  price_note    text,
  source        text,                                  -- producthunt / github / manual…
  source_url    text,
  content_hash  text unique,                           -- dedupe across sources
  launched_at   date,
  trend_score   numeric not null default 0,
  view_count    int not null default 0,
  save_count    int not null default 0,
  avg_rating    numeric not null default 0,
  rating_count  int not null default 0,
  status        publish_status not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- news  (headlines — support content, always links out)
-- ---------------------------------------------------------------------------
create table if not exists news (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  url          text unique not null,
  snippet      text not null default '',
  ai_summary   jsonb not null default '[]'::jsonb,
  image_url    text,
  source       text,
  category     text references categories(slug) on update cascade,
  content_hash text unique,
  published_at timestamptz not null default now(),
  status       publish_status not null default 'pending',
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- posts  (community share)
-- ---------------------------------------------------------------------------
create table if not exists posts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  tool_id       uuid references tools(id) on delete set null,
  content       text not null,
  image_url     text,
  like_count    int not null default 0,
  comment_count int not null default 0,
  status        content_status not null default 'active',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- reviews  (rating + short review of a tool; one per user per tool)
-- ---------------------------------------------------------------------------
create table if not exists reviews (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  tool_id    uuid not null references tools(id) on delete cascade,
  rating     int not null check (rating between 1 and 5),
  body       text not null default '',
  like_count int not null default 0,
  status     content_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, tool_id)
);

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
create table if not exists comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references posts(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  body       text not null,
  status     content_status not null default 'active',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- likes  (polymorphic: post | comment | review)
-- ---------------------------------------------------------------------------
create table if not exists likes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment','review')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  unique (user_id, target_type, target_id)
);

-- ---------------------------------------------------------------------------
-- bookmarks
-- ---------------------------------------------------------------------------
create table if not exists collections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now()
);

create table if not exists bookmarks (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  tool_id       uuid not null references tools(id) on delete cascade,
  collection_id uuid references collections(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (user_id, tool_id)
);

-- ---------------------------------------------------------------------------
-- follows  (polymorphic: user | tool)
-- ---------------------------------------------------------------------------
create table if not exists follows (
  id          uuid primary key default gen_random_uuid(),
  follower_id uuid not null references profiles(id) on delete cascade,
  target_type text not null check (target_type in ('user','tool')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  unique (follower_id, target_type, target_id)
);

-- ---------------------------------------------------------------------------
-- reports  (moderation)
-- ---------------------------------------------------------------------------
create table if not exists reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references profiles(id) on delete set null,
  target_type text not null check (target_type in ('post','comment','review','tool')),
  target_id   uuid not null,
  reason      text not null default '',
  status      text not null default 'open' check (status in ('open','resolved')),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  type       text not null,
  payload    jsonb not null default '{}'::jsonb,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- devices  (FCM tokens)
-- ---------------------------------------------------------------------------
create table if not exists devices (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  fcm_token  text unique not null,
  platform   text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes (see §12 scalability)
-- ---------------------------------------------------------------------------
create index if not exists idx_tools_status_trend on tools (status, trend_score desc);
create index if not exists idx_tools_status_created on tools (status, created_at desc);
create index if not exists idx_tools_category on tools (category);
create index if not exists idx_tools_tags on tools using gin (tags);
create index if not exists idx_tools_name_trgm on tools using gin (name gin_trgm_ops);
create index if not exists idx_tools_tagline_trgm on tools using gin (tagline gin_trgm_ops);

create index if not exists idx_news_status_pub on news (status, published_at desc);

create index if not exists idx_posts_status_created on posts (status, created_at desc);
create index if not exists idx_posts_tool on posts (tool_id);
create index if not exists idx_posts_user on posts (user_id);

create index if not exists idx_reviews_tool on reviews (tool_id);
create index if not exists idx_reviews_user on reviews (user_id);

create index if not exists idx_comments_post on comments (post_id);
create index if not exists idx_likes_target on likes (target_type, target_id);
create index if not exists idx_bookmarks_user on bookmarks (user_id);
create index if not exists idx_follows_target on follows (target_type, target_id);
create index if not exists idx_reports_status on reports (status, created_at desc);
create index if not exists idx_notifications_user on notifications (user_id, read);

-- ---------------------------------------------------------------------------
-- Enable Row Level Security on every table (policies live in 0002_rls.sql).
-- ---------------------------------------------------------------------------
alter table profiles       enable row level security;
alter table categories     enable row level security;
alter table tools          enable row level security;
alter table news           enable row level security;
alter table posts          enable row level security;
alter table reviews        enable row level security;
alter table comments       enable row level security;
alter table likes          enable row level security;
alter table collections    enable row level security;
alter table bookmarks      enable row level security;
alter table follows        enable row level security;
alter table reports        enable row level security;
alter table notifications  enable row level security;
alter table devices        enable row level security;

-- ===== migrations/0002_rls.sql =====
-- ============================================================================
-- Liz — Row Level Security policies
-- Migration 0002. Principle: deny by default, allow explicitly (§9, §13).
--   * Anyone (incl. guests / anon) can READ published/active content.
--   * Users may write/update/delete only their OWN rows.
--   * Moderators/admins may hide/remove any content.
--   * Ingestion uses the service role, which BYPASSES RLS entirely.
-- ============================================================================

-- Helper: is the current user a moderator or admin?
create or replace function is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role in ('moderator','admin')
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles are public" on profiles
  for select using (true);

create policy "insert own profile" on profiles
  for insert with check (auth.uid() = id);

create policy "update own profile" on profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "mods update any profile" on profiles
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- categories  (read-only to clients; writes via service role)
-- ---------------------------------------------------------------------------
create policy "categories are public" on categories
  for select using (true);

-- ---------------------------------------------------------------------------
-- tools
-- ---------------------------------------------------------------------------
create policy "read published tools" on tools
  for select using (status = 'published' or is_moderator());

create policy "mods manage tools" on tools
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- news
-- ---------------------------------------------------------------------------
create policy "read published news" on news
  for select using (status = 'published' or is_moderator());

create policy "mods manage news" on news
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- posts
-- ---------------------------------------------------------------------------
create policy "read active posts" on posts
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own posts" on posts
  for insert with check (auth.uid() = user_id);

create policy "update own posts" on posts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own posts" on posts
  for delete using (auth.uid() = user_id);

create policy "mods moderate posts" on posts
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- reviews
-- ---------------------------------------------------------------------------
create policy "read active reviews" on reviews
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own reviews" on reviews
  for insert with check (auth.uid() = user_id);

create policy "update own reviews" on reviews
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own reviews" on reviews
  for delete using (auth.uid() = user_id);

create policy "mods moderate reviews" on reviews
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
create policy "read active comments" on comments
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own comments" on comments
  for insert with check (auth.uid() = user_id);

create policy "update own comments" on comments
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own comments" on comments
  for delete using (auth.uid() = user_id);

create policy "mods moderate comments" on comments
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- likes
-- ---------------------------------------------------------------------------
create policy "likes are public" on likes
  for select using (true);

create policy "like as self" on likes
  for insert with check (auth.uid() = user_id);

create policy "unlike own" on likes
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- collections + bookmarks  (private to the owner)
-- ---------------------------------------------------------------------------
create policy "own collections" on collections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own bookmarks" on bookmarks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- follows
-- ---------------------------------------------------------------------------
create policy "follows are public" on follows
  for select using (true);

create policy "follow as self" on follows
  for insert with check (auth.uid() = follower_id);

create policy "unfollow own" on follows
  for delete using (auth.uid() = follower_id);

-- ---------------------------------------------------------------------------
-- reports  (users create; only mods read/update)
-- ---------------------------------------------------------------------------
create policy "create report as self" on reports
  for insert with check (auth.uid() = reporter_id);

create policy "mods read reports" on reports
  for select using (is_moderator());

create policy "mods resolve reports" on reports
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- notifications + devices  (private to the owner)
-- ---------------------------------------------------------------------------
create policy "own notifications" on notifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own devices" on devices
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ===== migrations/0003_functions.sql =====
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

-- ===== migrations/0004_news_realtime.sql =====
-- ============================================================================
-- Liz — Technology News Feed: Realtime + (optional) scheduled ingestion.
-- Migration 0004. Safe to re-run.
-- ============================================================================

-- 1) Enable Supabase Realtime on the news table so newly-ingested articles are
--    pushed to connected clients instantly (the app's live feed).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'news'
  ) then
    alter publication supabase_realtime add table public.news;
  end if;
end $$;

-- Helps the feed query (already created in 0001, repeated here for fresh setups).
create index if not exists idx_news_status_pub on news (status, published_at desc);

-- ----------------------------------------------------------------------------
-- 2) OPTIONAL in-database scheduler (pg_cron + pg_net).
--    The RECOMMENDED scheduler is the free GitHub Actions workflow
--    (.github/workflows/fetch-news.yml) — it keeps keys out of the database.
--    If you'd rather schedule inside Postgres, uncomment the block below and
--    replace <PROJECT_REF> and <SERVICE_ROLE_KEY>. Prefer storing the key in
--    Supabase Vault rather than inline.
-- ----------------------------------------------------------------------------
--
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule(
--   'fetch-news-hourly',
--   '0 * * * *',                       -- top of every hour
--   $$
--     select net.http_post(
--       url     := 'https://<PROJECT_REF>.functions.supabase.co/fetch-news',
--       headers := jsonb_build_object(
--         'Content-Type', 'application/json',
--         'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
--       ),
--       body    := '{}'::jsonb
--     );
--   $$
-- );

-- ===== migrations/0005_storage.sql =====
-- ============================================================================
-- Liz — Storage: buckets + access policies for avatars and post images.
-- Migration 0005. Safe to re-run.
--
-- Convention: files are stored under a per-user folder — "<user_id>/<file>",
-- so a user can only write within their own prefix, while reads are public
-- (avatars and post images are shown to everyone).
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',     'avatars',     true, 5242880,  array['image/jpeg','image/png','image/webp']),
  ('post-images', 'post-images', true, 10485760, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Public read for both buckets ------------------------------------------------
drop policy if exists "public read avatars" on storage.objects;
create policy "public read avatars" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "public read post-images" on storage.objects;
create policy "public read post-images" on storage.objects
  for select using (bucket_id = 'post-images');

-- Authenticated users manage only files under their own "<uid>/" folder -------
drop policy if exists "own avatar writes" on storage.objects;
create policy "own avatar writes" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "own post-image writes" on storage.objects;
create policy "own post-image writes" on storage.objects
  for all to authenticated
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ===== migrations/0006_retention.sql =====
-- ============================================================================
-- Liz — data retention / housekeeping.
-- Migration 0006. Keeps the database lean automatically so it stays well within
-- limits regardless of how long the hourly news ingestion runs.
-- Safe to re-run.
--
-- Rationale: `news` is the only high-churn table (the hourly fetch-news job adds
-- ~80–100 rows/hour). A "latest tech news" feed only needs recent items, so we
-- keep a rolling window and delete older rows nightly. Everything else in the
-- schema is low-volume and needs no retention.
-- ============================================================================

create extension if not exists pg_cron;

-- Keep ~30 days of news; delete older nightly at 03:30 UTC.
-- (cron.schedule upserts by job name, so re-running just updates it.)
select cron.schedule(
  'prune-old-news',
  '30 3 * * *',
  $$ delete from public.news where published_at < now() - interval '30 days'; $$
);

-- Keep read notifications for 30 days (relevant once FCM push lands).
select cron.schedule(
  'prune-read-notifications',
  '35 3 * * *',
  $$ delete from public.notifications where read = true and created_at < now() - interval '30 days'; $$
);

-- Optional: also cap news to the most recent N rows as a hard ceiling. Uncomment
-- to enable (belt-and-suspenders alongside the time-based prune above).
-- select cron.schedule(
--   'cap-news-rows', '40 3 * * *',
--   $$ delete from public.news where id in (
--        select id from public.news order by published_at desc offset 5000
--      ); $$
-- );

-- ===== seed.sql =====
-- ============================================================================
-- Liz — seed content (categories, tools, news)
-- Mirrors the app's bundled mock data so a fresh project launches with a full,
-- browsable catalog — the "no empty room" rule (§16, Phase 1).
-- Community seed (profiles/posts/reviews) requires real auth users; see
-- seed_community.sql.
-- Safe to re-run: uses ON CONFLICT upserts on slug/url.
-- ============================================================================

insert into categories (name, slug, icon) values
  ('AI Writing',   'ai-writing',      'edit'),
  ('Video',        'ai-video',        'movie'),
  ('Image',        'ai-image',        'image'),
  ('Audio',        'ai-audio',        'graphic_eq'),
  ('Design',       'ai-design',       'brush'),
  ('Dev Tools',    'ai-dev',          'code'),
  ('Agents',       'ai-agents',       'smart_toy'),
  ('Productivity', 'ai-productivity', 'bolt'),
  ('Research',     'ai-research',     'science'),
  ('New Apps',     'new-apps',        'apps')
on conflict (slug) do update set name = excluded.name, icon = excluded.icon;

-- Tools -----------------------------------------------------------------------
insert into tools
  (name, slug, tagline, description, ai_summary, website_url, category, tags,
   platforms, pricing_type, price_note, source, trend_score, view_count,
   save_count, avg_rating, rating_count, status, launched_at, created_at)
values
  ('Scriptly','scriptly','Turn a rough outline into a finished script in seconds.',
   'Scriptly drafts video scripts, ad copy, and long-form articles from a short brief, keeping tone consistent and citing sources inline.',
   '["Generates full scripts from a one-line brief.","Keeps a consistent voice across an entire project.","Inline source citations you can verify."]',
   'https://example.com/scriptly','ai-writing',
   '{writing,copywriting,video,scripts}','{web}','freemium','Free tier: 10k words/mo',
   'producthunt',88,12400,940,4.6,128,'published',now()-interval '6 days',now()-interval '6 days'),

  ('Framecut','framecut','Edit video by editing the transcript.',
   'Framecut transcribes footage, then lets you cut, rearrange, and caption by editing text. Filler-word and silence removal is one click.',
   '["Edit video by editing its transcript.","One-click filler-word and silence removal.","Auto-captions in 30+ languages."]',
   'https://example.com/framecut','ai-video',
   '{video,editing,transcription,captions}','{web,mac}','freemium',null,
   'producthunt',94,20100,1720,4.7,240,'published',now()-interval '9 days',now()-interval '9 days'),

  ('Backdrop','backdrop','Remove and replace image backgrounds, free.',
   'A fast, free background remover with AI relight so the subject matches the new scene. Batch mode handles hundreds of product photos.',
   '["Free, high-quality background removal.","AI relights the subject to match new scenes.","Batch mode for product photography."]',
   'https://example.com/backdrop','ai-image',
   '{image,background,ecommerce,design}','{web,ios,android}','free',null,
   'github',76,8800,610,4.4,88,'published',now()-interval '21 days',now()-interval '21 days'),

  ('Vocalize','vocalize','Studio-quality voiceover from text.',
   'Vocalize produces natural narration with controllable emotion and pacing. Clone your voice with a two-minute sample.',
   '["Natural narration with emotion controls.","Voice cloning from a 2-minute sample.","Export broadcast-ready audio."]',
   'https://example.com/vocalize','ai-audio',
   '{audio,voice,tts,podcast}','{web}','paid','From $12/mo',
   'producthunt',71,9600,540,4.3,76,'published',now()-interval '18 days',now()-interval '18 days'),

  ('Layoutly','layoutly','Describe a UI, get a Figma-ready design.',
   'Layoutly turns a text prompt into editable, on-brand UI layouts. Export to Figma or copy production React.',
   '["Text-to-UI in seconds, fully editable.","Exports Figma files and React code.","Learns your brand tokens."]',
   'https://example.com/layoutly','ai-design',
   '{design,ui,figma,frontend}','{web}','freemium',null,
   'producthunt',90,15200,1310,4.5,165,'published',now()-interval '5 days',now()-interval '5 days'),

  ('Reviewer','reviewer','An AI pair that reviews your PRs.',
   'Reviewer comments on pull requests with context from your whole repo, flags risky changes, and suggests tests. Self-hostable.',
   '["Repo-aware pull-request reviews.","Flags risky diffs and missing tests.","Self-hostable for private code."]',
   'https://example.com/reviewer','ai-dev',
   '{dev,code-review,github,productivity}','{web}','freemium',null,
   'github',96,18700,1990,4.8,312,'published',now()-interval '4 days',now()-interval '4 days'),

  ('Taskloop','taskloop','An agent that runs your recurring workflows.',
   'Describe a repeatable task once; Taskloop schedules it, calls your tools, and reports back. Connects to 200+ apps.',
   '["Natural-language automation for recurring work.","Connects to 200+ apps and APIs.","Reports results on a schedule."]',
   'https://example.com/taskloop','ai-agents',
   '{agents,automation,workflow,productivity}','{web}','freemium',null,
   'producthunt',92,13900,1180,4.4,143,'published',now()-interval '7 days',now()-interval '7 days'),

  ('Inboxzero AI','inboxzero-ai','Triage, draft, and schedule your email.',
   'Sorts your inbox by intent, drafts replies in your voice, and surfaces the three emails that actually matter today.',
   '["Sorts email by intent automatically.","Drafts replies that sound like you.","Highlights what truly needs attention."]',
   'https://example.com/inboxzeroai','ai-productivity',
   '{productivity,email,assistant}','{web,ios,android}','freemium',null,
   'producthunt',68,7200,480,4.1,61,'published',now()-interval '24 days',now()-interval '24 days'),

  ('Sourcely','sourcely','Ask a question, get a cited research brief.',
   'Sourcely searches academic and web sources, then writes a structured brief with citations and a confidence note on each claim.',
   '["Cited research briefs from a question.","Confidence score on each claim.","Export to Notion, Docs, or Markdown."]',
   'https://example.com/sourcely','ai-research',
   '{research,citations,writing,academic}','{web}','freemium',null,
   'hackernews',82,10400,870,4.5,102,'published',now()-interval '12 days',now()-interval '12 days'),

  ('Moodboard','moodboard','Generate on-brand image sets instantly.',
   'Feed Moodboard a few references and it produces cohesive image sets for campaigns — consistent style, characters, and lighting.',
   '["Cohesive image sets from a few references.","Consistent characters and lighting.","Campaign-ready exports."]',
   'https://example.com/moodboard','ai-image',
   '{image,branding,marketing,design}','{web}','paid','From $19/mo',
   'producthunt',79,9100,700,4.2,84,'published',now()-interval '15 days',now()-interval '15 days'),

  ('Clipper','clipper','Turn long videos into short clips that pop.',
   'Clipper finds the best moments in a long video, reframes them vertically, adds captions, and schedules them to your socials.',
   '["Finds viral-worthy moments automatically.","Auto reframes and captions for shorts.","Schedules directly to socials."]',
   'https://example.com/clipper','ai-video',
   '{video,social,shorts,marketing}','{web}','freemium',null,
   'producthunt',85,11200,990,4.3,119,'published',now()-interval '11 days',now()-interval '11 days'),

  ('Querybird','querybird','Chat with your database in plain English.',
   'Ask questions about your data and Querybird writes the SQL, runs it safely on a read replica, and charts the result.',
   '["Plain-English questions become safe SQL.","Runs read-only on a replica.","Auto-charts every result."]',
   'https://example.com/querybird','ai-dev',
   '{dev,data,sql,analytics}','{web}','freemium',null,
   'github',87,10800,1020,4.6,133,'published',now()-interval '8 days',now()-interval '8 days'),

  ('Notewise','notewise','Your meetings, summarized and searchable.',
   'Joins your calls, writes structured notes with action items, and makes every past meeting searchable by topic or person.',
   '["Structured notes with action items.","Searchable archive of every meeting.","Syncs tasks to your tracker."]',
   'https://example.com/notewise','ai-productivity',
   '{productivity,meetings,notes,assistant}','{web,mac,windows}','freemium',null,
   'producthunt',64,6600,430,4.0,58,'published',now()-interval '30 days',now()-interval '30 days'),

  ('Personae','personae','Build a support agent from your docs.',
   'Point Personae at your help center and it deploys a support agent that answers accurately, escalates when unsure, and learns from tickets.',
   '["Support agent trained on your docs.","Escalates gracefully when unsure.","Improves from resolved tickets."]',
   'https://example.com/personae','ai-agents',
   '{agents,support,chatbot,saas}','{web}','paid','From $49/mo',
   'producthunt',73,8300,560,4.2,71,'published',now()-interval '17 days',now()-interval '17 days'),

  ('Palette','palette','AI color systems for real products.',
   'Generate accessible, on-brand color systems with light/dark variants and exportable design tokens — WCAG-checked automatically.',
   '["Accessible color systems in one click.","Light/dark variants + design tokens.","Automatic WCAG contrast checks."]',
   'https://example.com/palette','ai-design',
   '{design,color,accessibility,tokens}','{web}','free',null,
   'github',61,5900,520,4.5,64,'published',now()-interval '26 days',now()-interval '26 days'),

  ('Transcribe Go','transcribe-go','Offline transcription that respects privacy.',
   'A free, on-device transcription app. Nothing leaves your machine. Speaker labels, timestamps, and export to SRT.',
   '["On-device, private transcription.","Speaker labels and timestamps.","Export to SRT, VTT, and text."]',
   'https://example.com/transcribego','ai-audio',
   '{audio,transcription,privacy,free}','{mac,windows,linux}','free',null,
   'github',83,9900,1120,4.7,156,'published',now()-interval '13 days',now()-interval '13 days'),

  ('Pitchdeck AI','pitchdeck-ai','From idea to investor deck in minutes.',
   'Describe your startup and Pitchdeck AI builds a structured, designed deck with market sizing and a narrative arc you can edit.',
   '["Full investor deck from a description.","Includes market sizing and narrative.","Fully editable, on-brand slides."]',
   'https://example.com/pitchdeckai','new-apps',
   '{startup,slides,productivity,design}','{web}','freemium',null,
   'producthunt',70,7800,650,4.1,69,'published',now()-interval '19 days',now()-interval '19 days'),

  ('Refactory','refactory','Modernize legacy code, safely.',
   'Refactory proposes incremental refactors with tests, explains each change, and never touches more than you approve.',
   '["Incremental, test-backed refactors.","Explains the why behind each change.","You approve every diff."]',
   'https://example.com/refactory','ai-dev',
   '{dev,refactoring,legacy,testing}','{web,vscode}','freemium',null,
   'github',89,11800,1240,4.6,148,'published',now()-interval '6 days',now()-interval '6 days'),

  ('Storysmith','storysmith','Interactive fiction, generated and playable.',
   'Write a premise and Storysmith generates a branching, playable story with consistent characters and memory of your choices.',
   '["Branching interactive fiction from a premise.","Characters that remember your choices.","Share playable stories with a link."]',
   'https://example.com/storysmith','new-apps',
   '{writing,games,fiction,creative}','{web,ios,android}','freemium',null,
   'producthunt',58,5100,390,3.9,47,'published',now()-interval '28 days',now()-interval '28 days'),

  ('Datasketch','datasketch','Clean messy spreadsheets with a prompt.',
   'Upload a chaotic CSV and Datasketch normalizes columns, fixes types, dedupes rows, and explains every transformation.',
   '["Prompt-driven spreadsheet cleaning.","Fixes types, dedupes, normalizes.","Full audit trail of every change."]',
   'https://example.com/datasketch','ai-productivity',
   '{data,spreadsheet,productivity,cleaning}','{web}','freemium',null,
   'hackernews',66,6900,500,4.2,63,'published',now()-interval '20 days',now()-interval '20 days'),

  ('Lensflow','lensflow','Text-to-video that keeps characters consistent.',
   'Generate short cinematic clips from prompts with the same character across shots — a long-standing pain point, solved.',
   '["Consistent characters across generated shots.","Cinematic camera controls.","Up to 30-second clips."]',
   'https://example.com/lensflow','ai-video',
   '{video,generation,film,creative}','{web}','paid','From $29/mo',
   'producthunt',97,22300,2140,4.4,201,'published',now()-interval '3 days',now()-interval '3 days'),

  ('Brief.ai','brief-ai','Your personalized morning tech digest.',
   'Brief.ai learns what you care about and delivers a 3-minute morning read across launches, papers, and releases.',
   '["Personalized 3-minute tech digest.","Covers launches, papers, releases.","Learns from what you open."]',
   'https://example.com/briefai','new-apps',
   '{productivity,news,digest,assistant}','{web,ios,android}','free',null,
   'producthunt',74,8600,720,4.3,91,'published',now()-interval '14 days',now()-interval '14 days'),

  ('Formcraft','formcraft','AI forms that adapt to each answer.',
   'Build conversational forms that branch intelligently, validate inputs, and summarize responses for you automatically.',
   '["Conversational forms that branch by answer.","Smart validation out of the box.","Auto-summarized responses."]',
   'https://example.com/formcraft','ai-productivity',
   '{productivity,forms,nocode,saas}','{web}','freemium',null,
   'producthunt',55,4700,340,4.0,42,'published',now()-interval '25 days',now()-interval '25 days'),

  ('Coversmith','coversmith','Tailored cover letters from a job link.',
   'Paste a job posting and your resume; Coversmith writes a specific, honest cover letter and flags gaps to address.',
   '["Job-specific cover letters in seconds.","Flags gaps between you and the role.","Keeps your authentic voice."]',
   'https://example.com/coversmith','ai-writing',
   '{writing,career,jobs,productivity}','{web}','free',null,
   'hackernews',60,5600,470,4.1,55,'published',now()-interval '22 days',now()-interval '22 days')
on conflict (slug) do nothing;

-- News ------------------------------------------------------------------------
insert into news (title, url, snippet, ai_summary, source, category, published_at, status)
values
  ('A wave of "transcript-first" video editors is reshaping creator workflows',
   'https://example.com/news/transcript-first-editors',
   'Editing footage by editing text is moving from novelty to default, with several tools crossing the usability threshold this month.',
   '["Transcript-based editing is going mainstream.","Turnaround times are dropping sharply.","Captions and clipping are now table stakes."]',
   'techcrunch','ai-video',now()-interval '1 day','published'),
  ('Repo-aware code review agents show real defect-catch gains in early trials',
   'https://example.com/news/repo-aware-review',
   'Teams report agents catching bugs that slipped past human reviewers when given full-repository context.',
   '["Full-repo context beats single-diff review.","Early teams report real defect catches.","Self-hosting eases private-code concerns."]',
   'hackernews','ai-dev',now()-interval '2 days','published'),
  ('On-device transcription hits quality parity with cloud services',
   'https://example.com/news/on-device-transcription',
   'New open models make private, offline transcription genuinely competitive for the first time.',
   '["Offline transcription now rivals the cloud.","Privacy-sensitive fields are early adopters.","Open models drive the shift."]',
   'arstechnica','ai-audio',now()-interval '3 days','published')
on conflict (url) do nothing;

-- Compute initial trend scores from the seeded engagement.
select refresh_trend_scores();
