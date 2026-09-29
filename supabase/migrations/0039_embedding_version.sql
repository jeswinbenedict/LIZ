-- ============================================================================
-- Liz — re-embed with summaries. Migration 0039. Safe to re-run.
--
-- A tool's search vector now includes its AI summary (_shared/embed.ts,
-- EMBEDDING_VERSION = 'gte-small+summary'). The queue compares against that
-- version, so every tool embedded the old way is picked up again by
-- embed-tools. ai_summary is added at the end of the view: `create or replace
-- view` can only append columns.
-- ============================================================================

create or replace view tools_needing_embedding as
  select id, name, tagline, description, category, tags, ai_summary
  from tools
  where status in ('published', 'pending')
    and (embedding is null or embedding_model is distinct from 'gte-small+summary');
