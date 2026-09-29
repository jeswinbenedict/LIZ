-- ============================================================================
-- Liz — ranked, typo-tolerant search. Migration 0041. Safe to re-run.
--
-- The search box matched substrings (ILIKE) and returned the first thirty rows
-- in no particular order, so an exact name could sit below a tool that merely
-- mentioned it, and "elevenlab" or "grammerly" found nothing. This ranks:
--
--   exact name  >  name starts with the words  >  every word matches (AND)
--   >  some words match (OR)  >  a name that is spelled nearly the same.
--
-- Uses the full-text document from migration 0040 and pg_trgm for spelling.
-- ============================================================================

create extension if not exists pg_trgm;

create index if not exists idx_tools_name_trgm
  on public.tools using gin (lower(name) gin_trgm_ops);

create or replace function public.search_tools(
  q            text,
  pricing      text default null,
  max_results  int  default 30
)
returns setof public.tools
language sql
stable
set search_path = public
as $$
  with input as (
    select lower(trim(coalesce(q, ''))) as term,
           websearch_to_tsquery('english', coalesce(q, '')) as all_words,
           nullif(replace(plainto_tsquery('english', coalesce(q, ''))::text,
                          ' & ', ' | '), '')::tsquery as any_word
  ),
  scored as (
    select t.id,
           (case when lower(t.name) = i.term then 10 else 0 end)
         + (case when lower(t.name) like i.term || '%' then 4 else 0 end)
         + (case when t.search_doc @@ i.all_words
                 then 2 + 10 * ts_rank_cd(t.search_doc, i.all_words) else 0 end)
         + (case when i.any_word is not null and t.search_doc @@ i.any_word
                 then ts_rank_cd(t.search_doc, i.any_word) else 0 end)
         + 3 * similarity(lower(t.name), i.term) as score
      from tools t, input i
     where t.status = 'published'
       and length(i.term) >= 2
       and (pricing is null or t.pricing_type::text = pricing)
       and (
         lower(t.name) like '%' || i.term || '%'
         or t.search_doc @@ i.all_words
         or (i.any_word is not null and t.search_doc @@ i.any_word)
         or lower(t.name) % i.term
       )
     order by score desc
     limit greatest(least(max_results, 50), 1)
  )
  select t.*
    from scored s
    join tools t on t.id = s.id
   order by s.score desc, t.momentum desc, t.name;
$$;

grant execute on function public.search_tools(text, text, int) to anon, authenticated;
