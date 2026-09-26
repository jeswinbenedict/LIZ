-- ============================================================================
-- Liz — a budget for the functions that must stay public. Migration 0029.
--
-- `ask-liz` and `logo` are anonymous on purpose: a visitor asks a question or
-- loads a page of logos without an account. But each ask-liz call runs an
-- embedding model, and each logo call fetches an image from an upstream
-- service, so "anonymous" cannot also mean "unlimited".
--
-- A fixed window rather than a sliding one. It admits a burst at a boundary,
-- which for a cost ceiling is fine, and it costs one upsert instead of a row
-- per request plus a sweep.
-- ============================================================================

create table if not exists rate_limits (
  bucket       text        not null,
  window_start timestamptz not null,
  hits         int         not null default 0,
  primary key (bucket, window_start)
);

comment on table rate_limits is
  'Fixed-window counters for the public Edge Functions. Written only by the '
  'service role via take_rate_limit(); never read by clients.';

alter table rate_limits enable row level security;
-- No policy: RLS on with no policy denies every client. The service role
-- bypasses RLS, and it is the only thing that should ever touch this.

-- ----------------------------------------------------------------------------
-- take_rate_limit — count this request, and say whether it is allowed.
--
-- Returns true when the caller is within budget. The insert and the increment
-- are one statement so two requests arriving together cannot both read the
-- same count and both decide they were under the limit.
-- ----------------------------------------------------------------------------
create or replace function take_rate_limit(
  bucket_key    text,
  max_hits      int,
  window_length interval default '1 hour'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_window timestamptz;
  new_count      int;
begin
  -- Floor the clock to the window, so every caller in the same period shares
  -- one row rather than each creating their own.
  current_window := to_timestamp(
    floor(extract(epoch from now()) / extract(epoch from window_length))
      * extract(epoch from window_length)
  );

  insert into rate_limits (bucket, window_start, hits)
  values (bucket_key, current_window, 1)
  on conflict (bucket, window_start)
    do update set hits = rate_limits.hits + 1
  returning hits into new_count;

  return new_count <= max_hits;
end $$;

revoke all on function take_rate_limit(text, int, interval) from public, anon, authenticated;

-- Old windows are dead weight the moment they close.
create or replace function prune_rate_limits()
returns void language sql security definer set search_path = public as $$
  delete from rate_limits where window_start < now() - interval '1 day';
$$;

select cron.schedule(
  'prune-rate-limits',
  '20 3 * * *',
  $$ select public.prune_rate_limits(); $$
);
