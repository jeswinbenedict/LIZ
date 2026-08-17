-- ============================================================================
-- Liz — unified trend ranking. Migration 0010. Safe to re-run.
--
-- Problem: curated tools were scored from raw engagement (hundreds of thousands)
-- while ingested GitHub tools used a tiny log formula (~90), so rankings and the
-- displayed "trend" number were incomparable across sources.
--
-- Fix: score EVERY tool on the same 0–100 scale:
--   70%  popularity  — log-scaled views + saves (comparable across sources)
--   30%  quality     — average rating
-- Then keep it fresh daily.
-- ============================================================================

create or replace function public.refresh_trend_scores()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.tools t set trend_score = sub.score
  from (
    select id,
      round(
        greatest(0, least(100,
            -- popularity: 0..70, log-scaled so 1M+ signal ~= full marks
            0.70 * least(1.0,
              ln(greatest(view_count, 0) + 5 * greatest(save_count, 0) + 10)
              / ln(1000000)
            ) * 100
            -- quality: 0..30 from average rating
          + 0.30 * (coalesce(avg_rating, 0) / 5.0) * 100
        ))
      ) as score
    from public.tools
  ) sub
  where t.id = sub.id;
end $$;

-- Apply now to every existing tool.
select public.refresh_trend_scores();

-- Keep the ranking normalized daily (runs just after fetch-tools at 04:15).
select cron.schedule(
  'refresh-trend-scores-daily',
  '30 4 * * *',
  $$ select public.refresh_trend_scores(); $$
);
