-- Run by CI on the freshly migrated database (supabase db query --local -f).
-- Proves the column guards of migration 0063 hold for a signed-in person
-- going through the API role, and that the edits they are allowed still work.
-- Any failure raises, which fails the job.

insert into public.profiles (id, username, display_name, role) values
  ('11111111-1111-4111-8111-111111111111', 'qa-user', 'QA', 'user'),
  ('22222222-2222-4222-8222-222222222222', 'qa-admin', 'QA admin', 'admin');

insert into public.reviews (user_id, tool_id, rating, body, status)
select '11111111-1111-4111-8111-111111111111', id, 4, 'fine', 'hidden'
from public.tools order by created_at limit 1;

-- As the user, through the API role: try to become an admin, and to put back
-- a review a moderator hid; also make the edits that are theirs to make.
set role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',
  false
);
update public.profiles set role = 'admin', display_name = 'QA renamed'
 where id = '11111111-1111-4111-8111-111111111111';
update public.reviews set status = 'active', body = 'edited', like_count = 999
 where user_id = '11111111-1111-4111-8111-111111111111';
reset role;

do $$
begin
  if (select role::text from public.profiles
       where id = '11111111-1111-4111-8111-111111111111') <> 'user' then
    raise exception 'a signed-in user made themselves admin';
  end if;
  if (select display_name from public.profiles
       where id = '11111111-1111-4111-8111-111111111111') <> 'QA renamed' then
    raise exception 'a signed-in user could not rename themselves';
  end if;
  if (select status::text from public.reviews
       where user_id = '11111111-1111-4111-8111-111111111111') <> 'hidden' then
    raise exception 'an author put back a review a moderator hid';
  end if;
  if (select like_count from public.reviews
       where user_id = '11111111-1111-4111-8111-111111111111') <> 0 then
    raise exception 'an author set their own like count';
  end if;
  if (select body from public.reviews
       where user_id = '11111111-1111-4111-8111-111111111111') <> 'edited' then
    raise exception 'an author could not edit their own review';
  end if;
end $$;

-- As the admin: hand out a role.
set role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}',
  false
);
update public.profiles set role = 'moderator'
 where id = '11111111-1111-4111-8111-111111111111';
reset role;

do $$
begin
  if (select role::text from public.profiles
       where id = '11111111-1111-4111-8111-111111111111') <> 'moderator' then
    raise exception 'an admin could not make someone a moderator';
  end if;
end $$;

select 'column guards hold' as result;
