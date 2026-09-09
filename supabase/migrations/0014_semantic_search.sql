-- ============================================================================
-- Liz — semantic tool search. Migration 0014. Safe to re-run.
--
-- Keyword matching cannot answer "remove image backgrounds" unless a tool
-- literally uses those words, so Ask Liz surfaced anything free and trending
-- instead. This stores an embedding per tool and matches on meaning.
--
-- Vectors are 384-dimensional because they come from `gte-small`, the model
-- built into the Supabase Edge Runtime — open source, no API key, no per-call
-- cost. Queries MUST be embedded with the same model or the distances are
-- meaningless.
-- ============================================================================

create extension if not exists vector;

alter table tools add column if not exists embedding vector(384);

-- Records what produced the current vector, so a model change can be detected
-- and backfilled rather than silently mixing incompatible embeddings.
alter table tools add column if not exists embedding_model text;
alter table tools add column if not exists embedded_at timestamptz;

-- HNSW beats ivfflat here: the catalog is small and grows continuously, and
-- HNSW needs no retraining as rows are added.
create index if not exists tools_embedding_idx
  on tools using hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- match_tools — nearest published tools by cosine similarity.
--
-- `1 - (a <=> b)` converts pgvector's cosine *distance* into a similarity in
-- [0,1] so callers can apply an honest relevance floor instead of always
-- returning the least-bad rows.
-- ---------------------------------------------------------------------------
create or replace function match_tools(
  query_embedding vector(384),
  match_count int default 5,
  min_similarity float default 0.3
)
returns table (
  id uuid,
  name text,
  slug text,
  tagline text,
  description text,
  category text,
  tags text[],
  pricing_type pricing_type,
  logo_url text,
  website_url text,
  trend_score numeric,
  similarity float
)
language sql
stable
as $$
  select
    t.id, t.name, t.slug, t.tagline, t.description, t.category, t.tags,
    t.pricing_type, t.logo_url, t.website_url, t.trend_score,
    1 - (t.embedding <=> query_embedding) as similarity
  from tools t
  where t.status = 'published'
    and t.embedding is not null
    and 1 - (t.embedding <=> query_embedding) >= min_similarity
  order by t.embedding <=> query_embedding
  limit greatest(match_count, 1);
$$;

-- Anyone may search; only the service role writes embeddings.
grant execute on function match_tools(vector, int, float) to anon, authenticated;

-- Rows still needing an embedding (new, or embedded by an older model).
create or replace view tools_needing_embedding as
  select id, name, tagline, description, category, tags
  from tools
  where status in ('published', 'pending')
    and (embedding is null or embedding_model is distinct from 'gte-small');
