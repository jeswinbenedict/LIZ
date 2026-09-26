-- ============================================================================
-- Liz — drop Collections. Migration 0035.
--
-- Collections had a table, a model and repository methods, and no screen at
-- all: nothing in the app could create one or show one. Confirmed empty before
-- this ran — zero rows in `collections`, and no bookmark pointing at one.
--
-- Removed rather than carried, by decision. Saved lists are short per person
-- today, so grouping them adds little yet. Adding it back later is a new table
-- and a nullable column, which is cheaper than keeping an unreachable feature
-- looking half-finished in the meantime.
-- ============================================================================

alter table bookmarks drop column if exists collection_id;

drop policy if exists "own collections" on collections;
drop table if exists collections;
