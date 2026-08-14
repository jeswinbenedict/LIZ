-- ============================================================================
-- Liz — push config via Supabase Vault (replaces ALTER DATABASE ... SET, which
-- Supabase blocks for non-superusers). Migration 0008. Safe to re-run.
--
-- notify_user() now reads the sender endpoint + auth key from Vault. Storing
-- them is a one-time step (see footer). Until both secrets exist, only in-app
-- notifications are written — push is skipped, never errored.
-- ============================================================================

create or replace function public.notify_user(
  target_user uuid,
  ntype       text,
  title       text,
  body        text,
  route       text default null,
  extra       jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text;
  fn_key text;
begin
  -- 1) Always record the in-app notification.
  insert into public.notifications (user_id, type, payload)
  values (
    target_user,
    ntype,
    jsonb_build_object('title', title, 'body', body, 'route', route)
      || coalesce(extra, '{}'::jsonb)
  );

  -- 2) Look up push config from Vault (best-effort).
  begin
    select decrypted_secret into fn_url
      from vault.decrypted_secrets where name = 'functions_url';
    select decrypted_secret into fn_key
      from vault.decrypted_secrets where name = 'service_role_key';
  exception when others then
    fn_url := null; fn_key := null;
  end;

  -- 3) Push only when both are present.
  if fn_url is not null and fn_url <> '' and fn_key is not null and fn_key <> '' then
    perform net.http_post(
      url     := fn_url || '/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || fn_key
      ),
      body    := jsonb_build_object(
        'user_id', target_user,
        'title',   title,
        'body',    body,
        'route',   route,
        'data',    extra
      )
    );
  end if;
end $$;

-- ============================================================================
-- ONE-TIME: store the two secrets (run in the Supabase SQL editor). The
-- functions_url is pre-set below; you only add the service_role key:
--
--   select vault.create_secret(
--     '<SERVICE_ROLE_KEY>', 'service_role_key', 'Push: service role bearer');
--
-- To rotate later: select vault.update_secret(id, '<new>') — find id via
--   select id, name from vault.secrets;
-- ============================================================================
