-- ============================================================================
-- Liz — community seed (starter reviews + posts) — TEMPLATE
-- Posts/reviews reference profiles, which reference auth.users, so you must
-- create the accounts first. Two options:
--
--   A) Create 2–3 users in the Supabase dashboard (Authentication → Users),
--      copy their UUIDs, and paste them below.
--   B) Sign up 2–3 users through the app, then run this with their UUIDs.
--
-- Replace the placeholder UUIDs, then run:  supabase db execute --file supabase/seed_community.sql
-- (or paste into the SQL editor). The rating triggers will recompute avg_rating.
-- ============================================================================

-- \set maya  '00000000-0000-0000-0000-000000000001'
-- \set devon '00000000-0000-0000-0000-000000000002'

do $$
declare
  maya  uuid := '00000000-0000-0000-0000-000000000001';  -- <-- replace
  devon uuid := '00000000-0000-0000-0000-000000000002';  -- <-- replace
  t_reviewer uuid;
  t_framecut uuid;
  t_lensflow uuid;
begin
  -- Ensure profiles exist / are named nicely.
  update profiles set display_name = 'Maya Chen', username = 'maya.builds',
    bio = 'Indie hacker. I try one new AI tool every day.' where id = maya;
  update profiles set display_name = 'Devon Wright', username = 'devon',
    role = 'moderator', bio = 'Staff engineer. Skeptical until proven useful.' where id = devon;

  select id into t_reviewer from tools where slug = 'reviewer';
  select id into t_framecut from tools where slug = 'framecut';
  select id into t_lensflow from tools where slug = 'lensflow';

  insert into reviews (user_id, tool_id, rating, body) values
    (devon, t_reviewer, 5, 'Caught a real race condition in my PR that two humans missed.'),
    (maya,  t_framecut, 5, 'Editing video by editing text cut my rough-cut time in half.')
  on conflict (user_id, tool_id) do nothing;

  insert into posts (user_id, tool_id, content) values
    (maya, t_lensflow, 'Day 12 of trying one new AI tool a day. Lensflow kept my character consistent across 6 shots. Wild.'),
    (devon, t_reviewer, 'Hot take: Reviewer front-loads the boring 80% of my PR reviews.');
end $$;
