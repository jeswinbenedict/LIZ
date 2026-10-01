-- ============================================================================
-- Liz — drop keyword_tools(). Migration 0054. Safe to re-run.
--
-- Written in 0040 as a second opinion for Ask Liz, measured, and not used:
-- it admitted wrong answers on common words. Nothing calls it (the search box
-- uses search_tools, 0041), and an unused function granted to anon is surface
-- with no purpose. The tsvector column it read stays; search_tools uses it.
-- ============================================================================

drop function if exists public.keyword_tools(text, int);
