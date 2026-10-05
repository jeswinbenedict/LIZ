-- Liz is for signed-in people, the catalog included.
--
-- Since 5 October 2026 the app puts every page behind sign-in. Until now the
-- data underneath it stayed public: these policies granted reading to the
-- role `public`, so anyone holding the anon key — every visitor's browser has
-- it — could list every published tool, story, review and profile through
-- /rest/v1. They now name `authenticated` instead.
--
-- What does not change:
--   * The conditions. A signed-in person reads exactly what they did before.
--   * Own-row and moderator policies (bookmarks, devices, notifications,
--     preferences, reports, error events): they already gave anon nothing.
--   * The service role, which bypasses row-level security: scrapers, cron,
--     the Edge Functions and n8n all read with it.
--   * track() and inserting an error report, which signed-out visitors on
--     the sign-in page still use.
--   * search_tools, similar_tools and match_tools run as the caller, so they
--     now find nothing for anon on their own.
--
-- Edge Functions that read the catalog with the service role check the caller
-- themselves (ask-liz, _shared/signed_in.ts).

alter policy "read published tools" on public.tools to authenticated;
alter policy "categories are public" on public.categories to authenticated;
alter policy "read published news" on public.news to authenticated;
alter policy "read links between published rows" on public.news_tools to authenticated;
alter policy "read changes of published tools" on public.tool_changes to authenticated;
alter policy "read snapshots of published tools" on public.tool_signal_snapshots to authenticated;

alter policy "read active reviews" on public.reviews to authenticated;
alter policy "read active posts" on public.posts to authenticated;
alter policy "read active comments" on public.comments to authenticated;
alter policy "profiles are public" on public.profiles to authenticated;
alter policy "follows are public" on public.follows to authenticated;
alter policy "likes are public" on public.likes to authenticated;
