-- ============================================================================
-- Liz — Row Level Security policies
-- Migration 0002. Principle: deny by default, allow explicitly (§9, §13).
--   * Anyone (incl. guests / anon) can READ published/active content.
--   * Users may write/update/delete only their OWN rows.
--   * Moderators/admins may hide/remove any content.
--   * Ingestion uses the service role, which BYPASSES RLS entirely.
-- ============================================================================

-- Helper: is the current user a moderator or admin?
create or replace function is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role in ('moderator','admin')
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles are public" on profiles
  for select using (true);

create policy "insert own profile" on profiles
  for insert with check (auth.uid() = id);

create policy "update own profile" on profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "mods update any profile" on profiles
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- categories  (read-only to clients; writes via service role)
-- ---------------------------------------------------------------------------
create policy "categories are public" on categories
  for select using (true);

-- ---------------------------------------------------------------------------
-- tools
-- ---------------------------------------------------------------------------
create policy "read published tools" on tools
  for select using (status = 'published' or is_moderator());

create policy "mods manage tools" on tools
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- news
-- ---------------------------------------------------------------------------
create policy "read published news" on news
  for select using (status = 'published' or is_moderator());

create policy "mods manage news" on news
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- posts
-- ---------------------------------------------------------------------------
create policy "read active posts" on posts
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own posts" on posts
  for insert with check (auth.uid() = user_id);

create policy "update own posts" on posts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own posts" on posts
  for delete using (auth.uid() = user_id);

create policy "mods moderate posts" on posts
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- reviews
-- ---------------------------------------------------------------------------
create policy "read active reviews" on reviews
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own reviews" on reviews
  for insert with check (auth.uid() = user_id);

create policy "update own reviews" on reviews
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own reviews" on reviews
  for delete using (auth.uid() = user_id);

create policy "mods moderate reviews" on reviews
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
create policy "read active comments" on comments
  for select using (status = 'active' or auth.uid() = user_id or is_moderator());

create policy "create own comments" on comments
  for insert with check (auth.uid() = user_id);

create policy "update own comments" on comments
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own comments" on comments
  for delete using (auth.uid() = user_id);

create policy "mods moderate comments" on comments
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- likes
-- ---------------------------------------------------------------------------
create policy "likes are public" on likes
  for select using (true);

create policy "like as self" on likes
  for insert with check (auth.uid() = user_id);

create policy "unlike own" on likes
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- collections + bookmarks  (private to the owner)
-- ---------------------------------------------------------------------------
create policy "own collections" on collections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own bookmarks" on bookmarks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- follows
-- ---------------------------------------------------------------------------
create policy "follows are public" on follows
  for select using (true);

create policy "follow as self" on follows
  for insert with check (auth.uid() = follower_id);

create policy "unfollow own" on follows
  for delete using (auth.uid() = follower_id);

-- ---------------------------------------------------------------------------
-- reports  (users create; only mods read/update)
-- ---------------------------------------------------------------------------
create policy "create report as self" on reports
  for insert with check (auth.uid() = reporter_id);

create policy "mods read reports" on reports
  for select using (is_moderator());

create policy "mods resolve reports" on reports
  for update using (is_moderator());

-- ---------------------------------------------------------------------------
-- notifications + devices  (private to the owner)
-- ---------------------------------------------------------------------------
create policy "own notifications" on notifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own devices" on devices
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
