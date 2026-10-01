-- ============================================================================
-- Liz — index review before launch. Migration 0046. Safe to re-run.
--
-- From `supabase inspect db index-stats` and a read of every foreign key on
-- 30 September 2026. The database is small (36 MB) and healthy; these are the
-- lookups that would become sequential scans as the tables fill.
--
-- Added:
--   bookmarks(tool_id)  The change-alert trigger asks "who saved this tool?"
--                       on every price or rank change (0044), and deleting a
--                       tool cascades through it. Only (user_id, tool_id) was
--                       indexed, which does not serve a lookup by tool.
--   comments(user_id)   Deleting an account cascades to its comments.
--   events(user_id)     Deleting an account detaches its events (set null),
--                       which scans the largest table Liz will have.
--
-- Dropped:
--   idx_tools_description_trgm (3 MB, never used). Search moved to the
--   full-text document in 0040/0041 and no query matches on description by
--   substring any more. It was the largest index in the database, maintained
--   on every tool update for nothing.
-- ============================================================================

create index if not exists idx_bookmarks_tool on public.bookmarks (tool_id);
create index if not exists idx_comments_user on public.comments (user_id);
create index if not exists idx_events_user
  on public.events (user_id) where user_id is not null;

drop index if exists public.idx_tools_description_trgm;
