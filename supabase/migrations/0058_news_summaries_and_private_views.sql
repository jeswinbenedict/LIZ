-- Two things.
--
-- 1. Quick takes for news. The News page has always had a folded "quick take"
--    under each story, but nothing ever wrote one: every row's ai_summary was
--    '[]'. summarize-news fills them in from this backlog, on the same terms
--    as summarize-tools (0015, 0026): three empty answers and a row leaves
--    the queue.
--
--    Only the last 48 hours: that is what the feed shows, and the archive of
--    several thousand stories would spend the free model quota on pages
--    nobody opens. Only stories with a real snippet: a quick take written
--    from a headline alone would be invented. Hacker News stories, whose
--    snippet is empty since 0057, are left without one.
--
-- 2. Views that read past row-level security. A view runs with its owner's
--    rights unless it says otherwise, so error_summary showed every crash
--    report — message and route — to anyone holding the public key, though
--    error_events lets only moderators read them; and the two backlog views
--    listed pending tools, including ones held back by the malware check.
--    security_invoker makes each view obey the caller's policies, and the
--    backlogs are for the service role alone.
--
--    CREATE OR REPLACE VIEW drops these options: a later migration that
--    redefines one of these views must say `with (security_invoker = true)`.

alter table public.news
  add column if not exists summary_attempts integer not null default 0;

create or replace view public.news_needing_summary
with (security_invoker = true) as
  select id, title, snippet, source
  from public.news
  where status = 'published'
    and coalesce(jsonb_array_length(ai_summary), 0) = 0
    and summary_attempts < 3
    and published_at > now() - interval '48 hours'
    and length(btrim(coalesce(snippet, ''))) >= 80
  order by published_at desc;

revoke all on public.news_needing_summary from public, anon, authenticated;

create or replace function public.note_news_summary_attempt(news_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update news
     set summary_attempts = summary_attempts + 1
   where id = news_id;
$$;

revoke all on function public.note_news_summary_attempt(uuid)
  from public, anon, authenticated;

-- Offset from backfill-summaries (10,25,40,55) so the two never share a
-- minute of the model's rate limit.
select cron.schedule(
  'backfill-news-summaries',
  '2,17,32,47 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
               where name = 'functions_url') || '/summarize-news',
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

alter view public.error_summary set (security_invoker = true);
alter view public.tools_needing_summary set (security_invoker = true);
alter view public.tools_needing_embedding set (security_invoker = true);
alter view public.tools_rising set (security_invoker = true);

revoke all on public.tools_needing_summary from anon, authenticated;
revoke all on public.tools_needing_embedding from anon, authenticated;
