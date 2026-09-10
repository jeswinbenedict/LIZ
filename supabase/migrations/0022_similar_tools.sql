-- "Tools like this one", from the embeddings already in the table.
--
-- Every published tool carries a gte-small vector for Ask Liz, and all 185 of
-- them are populated. Comparing a tool against its neighbours is the same
-- index lookup Ask Liz already does, minus the step that costs anything: no
-- model call, no query to embed, no external service. It is the most useful
-- thing sitting unused in this database.
--
-- Kept as SQL rather than done in the client, because sending a 384-dimension
-- vector to the browser so the browser can send it back is absurd.

create or replace function similar_tools(
  source_id uuid,
  match_count int default 6,
  min_similarity float default 0.75
)
returns table (
  id uuid,
  name text,
  slug text,
  tagline text,
  category text,
  tags text[],
  pricing_type pricing_type,
  logo_url text,
  website_url text,
  trend_score numeric,
  trend_rank int,
  save_count int,
  avg_rating numeric,
  rating_count int,
  similarity float
)
language sql
stable
as $$
  select
    t.id, t.name, t.slug, t.tagline, t.category, t.tags, t.pricing_type,
    t.logo_url, t.website_url, t.trend_score, t.trend_rank, t.save_count,
    t.avg_rating, t.rating_count,
    1 - (t.embedding <=> src.embedding) as similarity
  from tools t
  cross join (
    select embedding from tools where id = source_id and embedding is not null
  ) src
  where t.status = 'published'
    and t.embedding is not null
    -- A tool is always its own nearest neighbour.
    and t.id <> source_id
    and 1 - (t.embedding <=> src.embedding) >= min_similarity
  order by t.embedding <=> src.embedding
  limit greatest(match_count, 1);
$$;

-- The floor matters more here than in search. Ask Liz answers a question and
-- some answer is better than none; this fills a strip on a page that is
-- already complete without it, so showing six unrelated products to avoid an
-- empty row is a worse outcome than showing nothing.

grant execute on function similar_tools(uuid, int, float) to anon, authenticated;
