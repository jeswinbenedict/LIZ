-- Cut the "similar tools" list relative to its own best match.
--
-- 0022 used an absolute floor of 0.75, and measuring it against the live
-- catalog showed the floor never fires. Every embedding here is a description
-- of an AI tool, so the whole catalog sits in a narrow band. Taking Otter.ai,
-- a meeting transcriber, against all 184 others:
--
--   #1    0.909  Fireflies        the same product, different company
--   #5    0.857  cherry-studio    loosely related
--   #10   0.846  Google Workspace CLI
--   #20   0.840  ElevenLabs       voice synthesis, not transcription
--   #40   0.830  ChatGPT
--   #184  0.779  a metering/billing product
--
-- An absolute floor anywhere in that band is arbitrary: 0.84 keeps ElevenLabs
-- for a transcription tool, 0.86 throws away good matches for tools whose
-- neighbours are all a little further off. What separates signal from filler
-- is not the number itself but the drop from the best match — a tool with a
-- true twin has one, and a tool without one has no close second either.
--
-- So: keep neighbours within `window_size` of the top match, and never more
-- than match_count. A distinctive tool gets a short, sharp list; a generic one
-- gets a longer one; a tool with no real neighbour gets nothing, which is the
-- right answer for a strip the page is complete without.

create or replace function similar_tools(
  source_id uuid,
  match_count int default 6,
  min_similarity float default 0.80,
  window_size float default 0.05
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
  with src as (
    select embedding from tools
     where id = source_id and embedding is not null
  ),
  scored as (
    select
      t.id, t.name, t.slug, t.tagline, t.category, t.tags, t.pricing_type,
      t.logo_url, t.website_url, t.trend_score, t.trend_rank, t.save_count,
      t.avg_rating, t.rating_count,
      1 - (t.embedding <=> src.embedding) as similarity
    from tools t
    cross join src
    where t.status = 'published'
      and t.embedding is not null
      -- A tool is always its own nearest neighbour.
      and t.id <> source_id
    order by t.embedding <=> src.embedding
    limit greatest(match_count, 1)
  )
  select * from scored
  where similarity >= greatest(
    min_similarity,
    (select max(similarity) from scored) - window_size
  )
  order by similarity desc;
$$;

grant execute on function similar_tools(uuid, int, float, float)
  to anon, authenticated;

-- 0022's four-argument signature would otherwise linger and keep answering.
drop function if exists similar_tools(uuid, int, float);
