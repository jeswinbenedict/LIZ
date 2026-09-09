-- ============================================================================
-- Liz — tools still needing an AI summary. Migration 0015. Safe to re-run.
--
-- Every tool ingested from GitHub or the scraper arrives with an empty
-- ai_summary, because nothing called /summarize during ingestion. The detail
-- page then shows an empty "AI summary" section. This view is what the
-- summarize-tools function drains, mirroring tools_needing_embedding.
-- ============================================================================

create or replace view tools_needing_summary as
  select id, name, tagline, description
  from tools
  where status in ('published', 'pending')
    and coalesce(jsonb_array_length(ai_summary), 0) = 0
    and coalesce(description, '') <> '';
