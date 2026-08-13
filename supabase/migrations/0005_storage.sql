-- ============================================================================
-- Liz — Storage: buckets + access policies for avatars and post images.
-- Migration 0005. Safe to re-run.
--
-- Convention: files are stored under a per-user folder — "<user_id>/<file>",
-- so a user can only write within their own prefix, while reads are public
-- (avatars and post images are shown to everyone).
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',     'avatars',     true, 5242880,  array['image/jpeg','image/png','image/webp']),
  ('post-images', 'post-images', true, 10485760, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Public read for both buckets ------------------------------------------------
drop policy if exists "public read avatars" on storage.objects;
create policy "public read avatars" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "public read post-images" on storage.objects;
create policy "public read post-images" on storage.objects
  for select using (bucket_id = 'post-images');

-- Authenticated users manage only files under their own "<uid>/" folder -------
drop policy if exists "own avatar writes" on storage.objects;
create policy "own avatar writes" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "own post-image writes" on storage.objects;
create policy "own post-image writes" on storage.objects
  for all to authenticated
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);
