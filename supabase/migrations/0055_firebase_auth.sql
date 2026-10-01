-- ============================================================================
-- Liz — Firebase Authentication in front of this database. Migration 0055.
-- Safe to re-run.
--
-- Sign-in moves to Firebase (email and password, Google, its own emails and
-- two-step codes); every row stays here. Supabase accepts Firebase ID tokens
-- through its third-party auth integration (dashboard → Authentication →
-- Third-party Auth → Firebase, project lizzy-50dc0), and Postgres sees their
-- claims in auth.jwt() exactly as it saw its own.
--
-- One thing does not carry over: auth.uid() casts the token's `sub` to a
-- uuid, and a Firebase user id ("x3Kq…", 28 characters) is not one. Every
-- policy and function that called it would fail on the cast. So:
--
--   * Each Firebase account maps to a Liz user id (a uuid, as before) in
--     firebase_accounts, written by the firebase-session Edge Function, which
--     also puts that id into the account's custom claims as `liz_uid` along
--     with the `role: authenticated` claim Supabase requires.
--   * current_uid() returns that id: from the claim (no lookup), from the
--     table (the first minutes, before the claim is set), or auth.uid() for a
--     token Supabase issued itself — so nothing changes for a session that is
--     still on Supabase Auth while the app switches over.
--   * Every policy and function body that called auth.uid() is rewritten to
--     call current_uid(), and the migration fails if one is left.
--
-- Profiles no longer reference auth.users: a Firebase user has no row there.
-- The one existing account keeps its id; firebase-session links it when its
-- owner signs in to Firebase with the same, verified, email address.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Firebase account → Liz user id
-- ---------------------------------------------------------------------------
create table if not exists public.firebase_accounts (
  firebase_uid text primary key,
  user_id      uuid not null unique references public.profiles(id) on delete cascade,
  email        text,
  created_at   timestamptz not null default now()
);

alter table public.firebase_accounts enable row level security;
-- No policies: only the service role (firebase-session, delete-account) and
-- security-definer functions read or write it.

comment on table public.firebase_accounts is
  'Which Liz user id each Firebase Authentication account signs in as.';

-- ---------------------------------------------------------------------------
-- The caller's Liz user id
-- ---------------------------------------------------------------------------
create or replace function public.current_uid()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  claims jsonb := auth.jwt();
  claimed text;
begin
  if claims is null or claims ->> 'sub' is null then
    return null;
  end if;
  if coalesce(claims ->> 'iss', '') like 'https://securetoken.google.com/%' then
    claimed := claims ->> 'liz_uid';
    if claimed ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return claimed::uuid;
    end if;
    return (select user_id from firebase_accounts where firebase_uid = claims ->> 'sub');
  end if;
  return auth.uid();
end $$;

grant execute on function public.current_uid() to anon, authenticated, service_role;

-- Whether this session passed a second factor: Supabase says aal2, Firebase
-- names the factor it used.
create or replace function public.session_is_two_step()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
      or coalesce(auth.jwt() -> 'firebase' ->> 'sign_in_second_factor', '') <> '';
$$;

grant execute on function public.session_is_two_step() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Profiles stand on their own
-- ---------------------------------------------------------------------------
do $$
declare
  fk record;
begin
  for fk in
    select con.conname, rel.relname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
      join pg_class ref on ref.oid = con.confrelid
      join pg_namespace refns on refns.oid = ref.relnamespace
     where con.contype = 'f' and ns.nspname = 'public'
       and refns.nspname = 'auth' and ref.relname = 'users'
  loop
    execute format('alter table public.%I drop constraint %I', fk.relname, fk.conname);
  end loop;
end $$;

alter table public.profiles alter column id set default gen_random_uuid();

-- Crash reports from a deleted account keep no link to it.
do $$ begin
  alter table public.error_events
    add constraint error_events_user_id_profiles_fkey
    foreign key (user_id) references public.profiles(id) on delete set null;
exception when duplicate_object then null; end $$;

-- A Supabase Auth account deleted directly still takes its profile with it.
create or replace function public.on_auth_user_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from profiles where id = old.id;
  return old;
end $$;

drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted
  after delete on auth.users
  for each row execute function public.on_auth_user_deleted();

-- ---------------------------------------------------------------------------
-- auth.uid() → current_uid(), everywhere
-- ---------------------------------------------------------------------------
do $$
declare
  p record;
  f record;
  using_expr text;
  check_expr text;
  def text;
  left_over int;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname in ('public', 'storage')
       and (coalesce(qual, '') like '%auth.uid()%'
            or coalesce(with_check, '') like '%auth.uid()%')
  loop
    using_expr := replace(p.qual, 'auth.uid()', 'public.current_uid()');
    check_expr := replace(p.with_check, 'auth.uid()', 'public.current_uid()');
    if using_expr is not null then
      execute format('alter policy %I on %I.%I using (%s)',
        p.policyname, p.schemaname, p.tablename, using_expr);
    end if;
    if check_expr is not null then
      execute format('alter policy %I on %I.%I with check (%s)',
        p.policyname, p.schemaname, p.tablename, check_expr);
    end if;
  end loop;

  for f in
    select pr.oid
      from pg_proc pr
      join pg_namespace ns on ns.oid = pr.pronamespace
     where ns.nspname = 'public'
       and pr.prokind = 'f'
       and pr.proname <> 'current_uid'
       and pg_get_functiondef(pr.oid) like '%auth.uid()%'
  loop
    def := replace(pg_get_functiondef(f.oid), 'auth.uid()', 'public.current_uid()');
    execute def;
  end loop;

  select count(*) into left_over from (
    select 1 from pg_policies
     where schemaname in ('public', 'storage')
       and (coalesce(qual, '') like '%auth.uid()%'
            or coalesce(with_check, '') like '%auth.uid()%')
    union all
    select 1 from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
     where ns.nspname = 'public' and pr.prokind = 'f'
       and pr.proname <> 'current_uid'
       and pg_get_functiondef(pr.oid) like '%auth.uid()%'
  ) still;
  if left_over > 0 then
    raise exception 'auth.uid() still used in % policies or functions', left_over;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Moderator two-step, for either kind of token
-- ---------------------------------------------------------------------------
create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles
     where id = public.current_uid() and role in ('moderator', 'admin')
  )
  and (
    not coalesce(
      (select (value #>> '{}')::boolean from app_config
        where key = 'moderator_mfa_required'),
      false)
    or public.session_is_two_step()
  );
$$;

create or replace function public.require_moderator_mfa()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.session_is_two_step() or not exists (
    select 1 from profiles
     where id = public.current_uid() and role in ('moderator', 'admin')
  ) then
    return false;
  end if;
  update app_config
     set value = 'true'::jsonb, updated_at = now()
   where key = 'moderator_mfa_required' and value <> 'true'::jsonb;
  return true;
end $$;

revoke all on function public.require_moderator_mfa() from public, anon;
grant execute on function public.require_moderator_mfa() to authenticated;

-- ---------------------------------------------------------------------------
-- Linking a Firebase account to a Liz user id
-- ---------------------------------------------------------------------------
-- Called by firebase-session with the claims of a token it has verified.
-- Returns the Liz user id, or null when the account must verify its email
-- first: an address that already belongs to an existing Liz account is only
-- linked to it once Firebase says the address is verified, or anyone could
-- sign up with someone else's email and walk into their account.
create or replace function public.link_firebase_account(
  p_firebase_uid  text,
  p_email         text,
  p_email_verified boolean,
  p_display_name  text,
  p_avatar_url    text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  linked uuid;
  existing uuid;
  base_username text;
  final_username text;
begin
  select user_id into linked from firebase_accounts where firebase_uid = p_firebase_uid;
  if linked is not null then
    return linked;
  end if;

  -- An account from before the switch, with the same address.
  if p_email is not null then
    select u.id into existing
      from auth.users u
      join profiles pr on pr.id = u.id
     where lower(u.email) = lower(p_email)
       and not exists (select 1 from firebase_accounts fa where fa.user_id = u.id)
     limit 1;
  end if;

  if existing is not null then
    if not coalesce(p_email_verified, false) then
      return null;
    end if;
    insert into firebase_accounts (firebase_uid, user_id, email)
    values (p_firebase_uid, existing, p_email);
    return existing;
  end if;

  base_username := lower(split_part(coalesce(p_email, 'user'), '@', 1));
  base_username := regexp_replace(base_username, '[^a-z0-9_]', '', 'g');
  if base_username = '' then base_username := 'user'; end if;
  final_username := base_username;
  while exists (select 1 from profiles where username = final_username) loop
    final_username := base_username || '_' || substr(gen_random_uuid()::text, 1, 4);
  end loop;

  insert into profiles (username, display_name, avatar_url)
  values (
    final_username,
    coalesce(nullif(trim(p_display_name), ''), final_username),
    nullif(p_avatar_url, '')
  )
  returning id into linked;

  insert into firebase_accounts (firebase_uid, user_id, email)
  values (p_firebase_uid, linked, p_email);
  return linked;
end $$;

revoke all on function public.link_firebase_account(text, text, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.link_firebase_account(text, text, boolean, text, text)
  to service_role;
