-- One UPDATE policy per community table instead of two.
--
-- comments, posts, reviews and profiles each had "update own …" and
-- "mods moderate …" (or "mods update any profile"): two permissive policies
-- for the same command, which Postgres evaluates one after the other for
-- every row. Supabase's performance advisor flagged all four, for every role.
--
-- Same meaning, one policy: the author or a moderator may update a row, and
-- the row they leave must still be theirs or they must be a moderator (two
-- permissive policies are OR-ed, for USING and WITH CHECK alike; the
-- moderators' had no WITH CHECK, so it used its USING). Only signed-in people
-- can be either, so the policy names `authenticated`. `(select current_uid())`
-- is evaluated once per statement rather than once per row.

drop policy if exists "update own comments" on public.comments;
drop policy if exists "mods moderate comments" on public.comments;
create policy "authors and mods update comments" on public.comments
  for update to authenticated
  using ((select current_uid()) = user_id or (select is_moderator()))
  with check ((select current_uid()) = user_id or (select is_moderator()));

drop policy if exists "update own posts" on public.posts;
drop policy if exists "mods moderate posts" on public.posts;
create policy "authors and mods update posts" on public.posts
  for update to authenticated
  using ((select current_uid()) = user_id or (select is_moderator()))
  with check ((select current_uid()) = user_id or (select is_moderator()));

drop policy if exists "update own reviews" on public.reviews;
drop policy if exists "mods moderate reviews" on public.reviews;
create policy "authors and mods update reviews" on public.reviews
  for update to authenticated
  using ((select current_uid()) = user_id or (select is_moderator()))
  with check ((select current_uid()) = user_id or (select is_moderator()));

drop policy if exists "update own profile" on public.profiles;
drop policy if exists "mods update any profile" on public.profiles;
create policy "owners and mods update profiles" on public.profiles
  for update to authenticated
  using ((select current_uid()) = id or (select is_moderator()))
  with check ((select current_uid()) = id or (select is_moderator()));
