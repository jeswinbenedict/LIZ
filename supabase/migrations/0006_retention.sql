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
