-- ============================================================================
-- Liz — live tool ingestion schedule. Migration 0009. Safe to re-run.
--
-- Runs the fetch-tools Edge Function daily to pull trending AI projects from
-- GitHub (real logos via owner avatars) into `tools`. Reuses the Vault secrets
-- (functions_url + service_role_key) already set up for push notifications.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Daily at 04:15 UTC. cron.schedule upserts by job name, so re-running updates.
select cron.schedule(
  'fetch-tools-daily',
  '15 4 * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'functions_url') || '/fetch-tools',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  $$
);
