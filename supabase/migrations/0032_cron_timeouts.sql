-- ============================================================================
-- Liz — give the scheduled calls time to finish. Migration 0032.
--
-- Found the moment 0031 made HTTP results visible: `fetch-news-hourly` has been
-- timing out at exactly 5000 ms on every single run, every hour, since it was
-- created. pg_net's default timeout is 5 seconds and fetch-news pulls eight
-- feeds, which takes longer than that.
--
-- Nobody noticed because cron records the *SQL* as succeeded — net.http_post
-- returns a request id immediately — and because a GitHub Actions workflow
-- runs the same function hourly and does complete. The news feed has been kept
-- fresh entirely by the half nobody thought was load-bearing.
--
-- Two fixes, both here:
--   1. Every scheduled HTTP call gets a timeout matched to the work it starts.
--   2. fetch-news-hourly goes into version control. It was created by hand in
--      the dashboard — 0004 only carries it as a commented-out example — so
--      production has been running a job this repository does not describe.
-- ============================================================================

-- Sixty seconds covers the slowest observed run of the backfills with room to
-- spare; the news pull gets longer because it is eight upstream feeds, several
-- of which rate-limit and are retried.
select cron.schedule(
  'fetch-news-hourly',
  '0 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
               where name = 'functions_url') || '/fetch-news',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
                                         from vault.decrypted_secrets
                                        where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
  $$
);

select cron.schedule(
  'fetch-tools-daily',
  '15 4 * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
               where name = 'functions_url') || '/fetch-tools',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
                                         from vault.decrypted_secrets
                                        where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $$
);

select cron.schedule(
  'backfill-embeddings',
  '5,20,35,50 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
               where name = 'functions_url') || '/embed-tools',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
                                         from vault.decrypted_secrets
                                        where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $$
);

select cron.schedule(
  'backfill-summaries',
  '10,25,40,55 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
               where name = 'functions_url') || '/summarize-tools',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
                                         from vault.decrypted_secrets
                                        where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $$
);
