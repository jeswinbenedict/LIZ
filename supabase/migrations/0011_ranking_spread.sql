-- ============================================================================
-- Liz — spread the trend ranking so scores are distinct & properly ordered.
-- Migration 0011. Safe to re-run.
--
-- The 0010 formula capped popularity at 100, so every big tool saturated to the
-- same value (ChatGPT, Midjourney… all 98). Here we min-max normalize a rich
-- raw signal across the whole table into a 40–100 band, so the most popular tool
-- tops out near 100 and the rest fan out beneath it with distinct scores.
--
-- Live: the raw signal is view_count + save_count + rating_count + avg_rating —
-- all of which grow with real in-app usage — plus GitHub stars refreshed daily
-- by fetch-tools. The daily cron (refresh-trend-scores-daily) keeps it current.
-- ============================================================================

create or replace function public.refresh_trend_scores()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  lo numeric;
  hi numeric;
begin
  -- Rich raw score: log-scaled reach, weighted by rating quality.
  with raw as (
    select id,
      ln(greatest(view_count, 0)
          + 3 * greatest(save_count, 0)
          + 5 * greatest(rating_count, 0) + 1)
        * (0.7 + 0.06 * coalesce(avg_rating, 0)) as r
    from public.tools
  )
  select min(r), max(r) into lo, hi from raw;

  update public.tools t set trend_score = coalesce(
    round(
      40 + 60 * (
        (ln(greatest(view_count, 0)
            + 3 * greatest(save_count, 0)
            + 5 * greatest(rating_count, 0) + 1)
          * (0.7 + 0.06 * coalesce(avg_rating, 0))) - lo
      ) / nullif(hi - lo, 0)
    ),
    100
  );
end $$;

select public.refresh_trend_scores();
