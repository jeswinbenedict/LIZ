-- ============================================================================
-- Liz — write outside signals in one call. Migration 0038. Safe to re-run.
--
-- `python -m liz_scraper.signals` reads GitHub stars and Hacker News points
-- for every tool that has them. PostgREST can only bulk-write through an
-- upsert, and an upsert is an INSERT first: it fails on NOT NULL columns the
-- payload leaves out. So the batch comes here instead and is applied as
-- updates, then snapshotted and ranked in the same call.
-- ============================================================================

create or replace function public.apply_signals(rows jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  updated int;
begin
  if jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array';
  end if;

  with incoming as (
    select (r ->> 'id')::uuid                   as id,
           nullif(r ->> 'gh_repo', '')          as gh_repo,
           (r ->> 'gh_stars')::int              as gh_stars,
           nullif(r ->> 'hn_id', '')            as hn_id,
           (r ->> 'hn_points')::int             as hn_points,
           (r ->> 'hn_comments')::int           as hn_comments,
           r ? 'gh_stars'                       as has_stars,
           r ? 'hn_points'                      as has_points
      from jsonb_array_elements(rows) r
  )
  update tools t set
    gh_repo     = coalesce(i.gh_repo, t.gh_repo),
    gh_stars    = case when i.has_stars  then i.gh_stars    else t.gh_stars    end,
    hn_id       = coalesce(i.hn_id, t.hn_id),
    hn_points   = case when i.has_points then i.hn_points   else t.hn_points   end,
    hn_comments = case when i.has_points then i.hn_comments else t.hn_comments end,
    signals_at  = now()
  from incoming i
  where i.id = t.id;

  get diagnostics updated = row_count;

  perform snapshot_signals();
  perform refresh_trend_scores();
  return updated;
end $$;

revoke all on function public.apply_signals(jsonb) from public, anon, authenticated;
