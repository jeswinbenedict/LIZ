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
