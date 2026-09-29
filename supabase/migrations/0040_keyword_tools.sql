-- ============================================================================
-- Liz — a full-text document for every tool. Migration 0040. Safe to re-run.
--
-- A weighted tsvector (name over tagline over description), used by the
-- search box (search_tools, migration 0041). keyword_tools() was written to
-- give Ask Liz a second opinion on close calls just under its similarity
-- floor; measured against the evaluation set it admitted wrong answers on
-- common words ("post", "play"), so Ask Liz does not use it. It stays as a
-- plain keyword ranking.
--
-- The terms are OR-ed, not AND-ed: a question has words its answer will not
-- (turn, my, into), and requiring all of them finds nothing. The rank rewards
-- matching more of them, and weights name over tagline over description.
-- ============================================================================

alter table public.tools
  add column if not exists search_doc tsvector
  generated always as (
    setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(tagline, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'C')
  ) stored;

create index if not exists idx_tools_search_doc on public.tools using gin (search_doc);

create or replace function public.keyword_tools(q text, match_count int default 30)
returns table (id uuid, rank real)
language sql
stable
set search_path = public
as $$
  with query as (
    select nullif(
      replace(plainto_tsquery('english', coalesce(q, ''))::text, ' & ', ' | '),
      ''
    )::tsquery as tsq
  )
  select t.id, ts_rank_cd(t.search_doc, query.tsq) as rank
    from tools t, query
   where query.tsq is not null
     and t.status = 'published'
     and t.search_doc @@ query.tsq
   order by rank desc, t.id
   limit greatest(match_count, 1);
$$;

grant execute on function public.keyword_tools(text, int) to anon, authenticated;
