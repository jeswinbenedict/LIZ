-- ============================================================================
-- Liz — health alerts that reach a phone. Migration 0047. Safe to re-run.
--
-- check_system_health() runs hourly and, when something fails, notifies
-- admins — inside the app. Nobody reads an in-app notification at 3 a.m., so
-- a catalog that stopped updating overnight went unnoticed until someone
-- opened the admin console.
--
-- Failures (and the recovery after them) are now also pushed through ntfy
-- (https://ntfy.sh): free, open source, no account. Install the ntfy app,
-- subscribe to the topic stored in app_config.alert_ntfy_topic, and alerts
-- arrive as phone notifications. The topic is a random name that works like
-- a password, so it lives only in the database, never in the repository. A
-- self-hosted ntfy server can be used by changing alert_ntfy_server.
--
-- Same cooldown as the in-app alert: at most one failure push every six
-- hours, plus one "healthy again" when it clears.
-- ============================================================================

insert into public.app_config (key, value)
values ('alert_ntfy_server', '"https://ntfy.sh"'::jsonb),
       ('alert_state', '{"failing": false}'::jsonb)
on conflict (key) do nothing;

-- Pushes one message. Returns false when no topic is configured.
create or replace function public.push_alert(
  title    text,
  message  text,
  priority int default 4,
  tags     text[] default array['warning']
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  topic  text := (select value #>> '{}' from app_config where key = 'alert_ntfy_topic');
  server text := coalesce(
    (select value #>> '{}' from app_config where key = 'alert_ntfy_server'),
    'https://ntfy.sh');
begin
  if topic is null or topic = '' then
    return false;
  end if;
  -- ntfy's JSON publishing: POST to the server root with the topic in the body.
  perform net.http_post(
    url     := rtrim(server, '/'),
    body    := jsonb_build_object(
                 'topic', topic,
                 'title', left(title, 120),
                 'message', left(message, 1000),
                 'priority', priority,
                 'tags', to_jsonb(tags)),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  return true;
end $$;

revoke all on function public.push_alert(text, text, int, text[]) from public, anon, authenticated;

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
  state    jsonb := coalesce(
    (select value from app_config where key = 'alert_state'), '{}'::jsonb);
  last_push timestamptz := (state ->> 'pushed_at')::timestamptz;
begin
  for failing in
    select signal, value from system_health() where status = 'fail'
  loop
    failures := failures + 1;
    summary := summary || failing.signal || ' = ' || failing.value || '. ';
  end loop;

  if failures = 0 then
    -- Say so once when a failure clears, so the last word on a phone is not
    -- an alarm that has already been dealt with.
    if coalesce((state ->> 'failing')::boolean, false) then
      perform push_alert('Liz is healthy again',
                         'Every health signal is back to ok.', 3,
                         array['white_check_mark']);
      update app_config
         set value = jsonb_build_object('failing', false, 'pushed_at', now()),
             updated_at = now()
       where key = 'alert_state';
    end if;
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

  if last_push is null
     or last_push < now() - interval '6 hours'
     or not coalesce((state ->> 'failing')::boolean, false) then
    if push_alert('Liz needs attention', summary, 4, array['warning']) then
      update app_config
         set value = jsonb_build_object('failing', true, 'pushed_at', now()),
             updated_at = now()
       where key = 'alert_state';
    end if;
  end if;
end $$;
