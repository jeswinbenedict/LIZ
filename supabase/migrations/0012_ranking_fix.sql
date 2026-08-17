-- ============================================================================
-- Liz — refresh_trend_scores WHERE-clause fix. Migration 0012. Safe to re-run.
--
-- Supabase rejects an UPDATE without a WHERE clause (safety guard) when the
-- function is invoked over the API (e.g. from the refresh-signals Edge Function).
-- Rewrite the min-max normalization as an UPDATE ... FROM ... WHERE join so it
-- carries an explicit predicate, keeping the same 40-100 spread behavior.
-- ============================================================================

create or replace function public.refresh_trend_scores()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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
end $$;

select public.refresh_trend_scores();
