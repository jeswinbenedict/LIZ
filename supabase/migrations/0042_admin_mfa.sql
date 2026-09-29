-- ============================================================================
-- Liz — two-step verification for moderators. Migration 0042. Safe to re-run.
--
-- Every moderator power in the database goes through is_moderator(): reading
-- held tools and hidden posts, publishing, resolving reports, the health and
-- usage views. With a password alone, a phished admin account could publish
-- anything. Once required, those powers need a session that has passed a TOTP
-- check (Supabase puts that in the JWT as aal = 'aal2').
--
-- Switched on by the first moderator to verify an authenticator code, not by
-- this migration: turning it on before anyone has enrolled would lock every
-- admin out of the console that enrolment happens in. From then on it stays
-- on; turning it off takes the service role:
--   update app_config set value = 'false' where key = 'moderator_mfa_required';
-- ============================================================================

create table if not exists public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

comment on table public.app_config is
  'Project-wide switches read by security-definer functions. Never read by '
  'clients directly.';

alter table public.app_config enable row level security;
-- No policies: only security-definer functions and the service role touch it.

insert into public.app_config (key, value)
values ('moderator_mfa_required', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles
     where id = auth.uid() and role in ('moderator', 'admin')
  )
  and (
    not coalesce(
      (select (value #>> '{}')::boolean from app_config
        where key = 'moderator_mfa_required'),
      false)
    or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
  );
$$;

-- Called by the app right after a moderator verifies an authenticator code.
-- Only a moderator whose current session is already aal2 can turn it on, and
-- nothing here can turn it off.
create or replace function public.require_moderator_mfa()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' or not exists (
    select 1 from profiles
     where id = auth.uid() and role in ('moderator', 'admin')
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
