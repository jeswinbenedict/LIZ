-- ============================================================================
-- Liz — client error reporting. Migration 0016. Safe to re-run.
--
-- Nothing recorded crashes, so a failure in front of a real user left no trace
-- anywhere. Crashlytics does not support Flutter web, so errors are written
-- here instead: no third-party account, and the data stays in this project.
--
-- `fingerprint` groups repeats of the same fault so one broken screen reads as
-- a single problem with a count, rather than a thousand separate rows.
-- ============================================================================

create table if not exists error_events (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  message      text not null,
  stack        text,
  fingerprint  text not null,
  route        text,
  platform     text,
  app_version  text,
  -- Null for signed-out visitors. Set null rather than cascade-deleting the
  -- report: the fault still happened after the account is gone.
  user_id      uuid references auth.users(id) on delete set null,
  context      jsonb not null default '{}'::jsonb
);

create index if not exists error_events_created_idx
  on error_events (created_at desc);
create index if not exists error_events_fingerprint_idx
  on error_events (fingerprint, created_at desc);

alter table error_events enable row level security;

-- Anyone may report a crash, including signed-out visitors — those are exactly
-- the reports that would otherwise be lost. Nobody may read them back: a stack
-- trace can carry user content, so reading is left to moderators.
drop policy if exists "anyone can report an error" on error_events;
create policy "anyone can report an error" on error_events
  for insert with check (true);

drop policy if exists "mods read errors" on error_events;
create policy "mods read errors" on error_events
  for select using (is_moderator());

-- Most recent fault per fingerprint, with a count — the view to look at first.
create or replace view error_summary as
  select
    fingerprint,
    count(*)                        as occurrences,
    max(created_at)                 as last_seen,
    min(created_at)                 as first_seen,
    count(distinct user_id)         as affected_users,
    (array_agg(message order by created_at desc))[1] as latest_message,
    (array_agg(route   order by created_at desc))[1] as latest_route
  from error_events
  group by fingerprint;

-- Reports age out with the rest of the retention policy; keep a short window
-- so the table cannot grow without bound from a runaway client.
create or replace function prune_error_events()
returns void language sql security definer set search_path = public as $$
  delete from error_events where created_at < now() - interval '30 days';
$$;
