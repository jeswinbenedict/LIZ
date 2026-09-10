-- ============================================================================
-- Liz — don't nag hourly. Migration 0027.
--
-- Verified end to end against production: tripping client_errors_24h past 100
-- made the signal read 'fail', and check_system_health() notified the admin
-- with "Liz needs attention — client_errors_24h = 101."
--
-- Which also showed the flaw. The check runs hourly and most failures last
-- longer than an hour: ingestion breaking on a Friday would deliver the same
-- notification every hour until Monday. That is how an alert channel gets
-- muted, and a muted channel is worse than no channel, because it still looks
-- like monitoring.
--
-- So: at most one health alert every six hours. Long enough not to nag,
-- short enough that a problem which is still there keeps asking.
-- ============================================================================

create or replace function check_system_health()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  failing  record;
  admin    record;
  summary  text := '';
  failures int  := 0;
  recently boolean;
begin
  for failing in
    select signal, value from system_health() where status = 'fail'
  loop
    failures := failures + 1;
    summary := summary || failing.signal || ' = ' || failing.value || '. ';
  end loop;

  if failures = 0 then
    return;
  end if;

  for admin in select id from profiles where role = 'admin' loop
    -- Per admin rather than globally: someone added to the team mid-incident
    -- should hear about it rather than inherit another person's cooldown.
    select exists (
      select 1 from notifications
       where user_id = admin.id
         and type = 'health'
         and created_at > now() - interval '6 hours'
    ) into recently;

    if not recently then
      perform public.notify_user(
        admin.id,
        'health',
        'Liz needs attention',
        left(summary, 300),
        '/admin',
        jsonb_build_object('failures', failures)
      );
    end if;
  end loop;
end $$;
