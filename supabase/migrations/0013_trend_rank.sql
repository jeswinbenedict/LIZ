-- ============================================================================
-- Liz — unique leaderboard rank. Migration 0013. Safe to re-run.
--
-- A 0-100 score can't uniquely order ~150 tools (integer ties). Add an explicit
-- trend_rank (1 = top) assigned by row_number over the trend score, with stable
-- tiebreakers, so every tool has a distinct position. Recomputed with the score,
-- so it stays live as engagement + GitHub stars change.
-- ============================================================================

alter table public.tools add column if not exists trend_rank int;

create or replace function public.refresh_trend_scores()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 1) Unified 0-100 spread score (min-max over a rich signal).
  with raw as (
    select id,
      ln(greatest(view_count, 0)
          + 3 * greatest(save_count, 0)
          + 5 * greatest(rating_count, 0) + 1)
        * (0.7 + 0.06 * coalesce(avg_rating, 0)) as r
    from public.tools
  ),
  bounds as (select min(r) as lo, max(r) as hi from raw)
  update public.tools t
  set trend_score = coalesce(
        round(40 + 60 * (raw.r - bounds.lo) / nullif(bounds.hi - bounds.lo, 0)),
        100)
  from raw, bounds
  where t.id = raw.id;

  -- 2) Unique position among published tools (stable tiebreakers).
  with ranked as (
    select id, row_number() over (
      order by trend_score desc, view_count desc, save_count desc, created_at desc, id
    ) as rn
    from public.tools
    where status = 'published'
  )
  update public.tools t
  set trend_rank = ranked.rn
  from ranked
  where t.id = ranked.id;

  -- Non-published tools have no leaderboard position.
  update public.tools set trend_rank = null where status <> 'published';
end $$;

select public.refresh_trend_scores();
