-- ============================================================================
-- Liz — keep embeddings and summaries current. Migration 0025.
--
-- Found by the health check added in 0024, on its first run against
-- production: AI summary coverage had fallen to 53%. Nearly half of the 185
-- published tools showed an empty "AI summary" on their page — the section
-- that is the reason to open a tool page rather than read the card.
--
-- The cause is not a bug in the summariser. `embed-tools` and
-- `summarize-tools` both exist, are idempotent, and their own headers say they
-- are safe to run on a schedule after every ingestion pass. Neither was ever
-- scheduled. They were run by hand once, coverage read 100%, and then the
-- nightly fetch kept adding tools that nothing ever summarised.
--
-- Both drain a view in small batches — the embedder dies at batch sizes above
-- about five, and each summary costs an LLM round trip — so they are designed
-- to be called repeatedly rather than once with a large limit. Running every
-- fifteen minutes gives roughly 380 summaries and 480 embeddings a day of
-- capacity against a daily intake of a few dozen tools: enough to clear the
-- backlog within hours and then sit idle, which costs one empty query per run.
-- ============================================================================

-- Offset from each other and from the 04:15 fetch, so a batch is never
-- competing with the ingestion that creates its work.
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
      body := '{}'::jsonb
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
      body := '{}'::jsonb
    );
  $$
);
