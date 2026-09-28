-- Remember each tool's "What's new" for a while.
--
-- tool-updates asked GitHub and Google News afresh for every tool page view.
-- GitHub's unauthenticated budget is 60 requests an hour for everything this
-- project runs, and Google News answered about half the calls from Supabase's
-- addresses with 503 (measured 28 September: 4 of 8 tools). A page view that
-- landed on a refusal showed an empty "What's new" even when the same tool had
-- shown ten items a minute earlier.
--
-- One row per tool source. Fresh for 12 hours; after that a new answer is
-- fetched, and if that fails the last good one is served for up to a week.

create table if not exists public.tool_updates_cache (
  cache_key  text primary key,          -- 'gh:owner/repo' or 'news:<name>'
  kind       text not null,             -- 'releases' | 'news'
  items      jsonb not null default '[]'::jsonb,
  source     text,                      -- where the items came from
  fetched_at timestamptz not null default now()
);

comment on table public.tool_updates_cache is
  'Cached "What''s new" answers for tool-updates. Written and read only by '
  'that function with the service role; never read by clients.';

-- On with no policies: only the service role, which bypasses RLS, can reach it.
alter table public.tool_updates_cache enable row level security;
