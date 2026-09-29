-- ============================================================================
-- Liz — how long usage events are kept. Migration 0043. Safe to re-run.
--
-- The privacy policy promises two limits on the event log (migration 0037):
-- the words someone typed into search or Ask Liz go after 90 days, and the
-- events themselves after 13 months. A policy is only true if something
-- enforces it, so this does, nightly.
--
-- The daily snapshots keep the totals Rising needs (tool_signal_snapshots),
-- so pruning old events loses no history — only the individual rows.
-- ============================================================================

create or replace function public.prune_events()
returns void
language sql
security definer
set search_path = public
as $$
  update events
     set props = props - 'q'
   where name in ('search', 'ask')
     and props ? 'q'
     and created_at < now() - interval '90 days';

  delete from events where created_at < now() - interval '13 months';
$$;

revoke all on function public.prune_events() from public, anon, authenticated;

select cron.schedule(
  'prune-events',
  '40 3 * * *',
  $$ select public.prune_events(); $$
);
