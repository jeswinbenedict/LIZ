-- What Supabase's security advisor found, 2 October 2026.
--
-- A function is executable by everyone unless it says otherwise, and a
-- SECURITY DEFINER one runs with its owner's rights. Several meant only for
-- triggers and cron were callable by anyone holding the public key, through
-- /rest/v1/rpc:
--
--   * notify_user(target_user, …) — the serious one. It writes a notification
--     into any user's inbox and sends them a browser push, with nothing
--     checking the caller: a ready-made phishing channel.
--   * check_system_health() — sends the owner a push alert.
--   * prune_error_events(), prune_rate_limits(), failed_job_calls() — cron's.
--   * Every trigger function. These cannot be called outside a trigger, so
--     this only quiets the advisor; a trigger runs whatever the caller's
--     rights.
--
-- Triggers and pg_cron run as the owner and are unaffected. What the app
-- calls stays callable: search_tools, similar_tools and track for everyone;
-- system_health, recent_job_runs, recent_job_responses, usage_summary and
-- require_moderator_mfa for signed-in moderators (each checks is_moderator()
-- itself); current_uid() and is_moderator() for the policies that use them.
--
-- Also: a fixed search_path on the functions that lacked one, and no
-- listing of the avatar and post-image buckets — public buckets serve their
-- files by URL without a SELECT policy, so the only thing those policies
-- added was a list of every user's folder.

do $$
declare
  fn regprocedure;
begin
  -- Not for callers at all.
  for fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname in ('notify_user', 'check_system_health', 'failed_job_calls',
                          'prune_error_events', 'prune_rate_limits')
            or pg_get_function_result(p.oid) = 'trigger')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
  end loop;

  -- Moderator tools: signed in only (each also checks is_moderator()).
  for fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('system_health', 'recent_job_runs', 'recent_job_responses',
                         'usage_summary', 'require_moderator_mfa')
  loop
    execute format('revoke execute on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;

  -- A fixed search_path, so a caller's own schema cannot shadow what these
  -- functions mean by a table or operator name.
  for fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('touch_updated_at', 'match_tools', 'similar_tools',
                         'compact_count', 'needs_tech_context', 'session_is_two_step',
                         'has_tech_context', 'ambiguous_tool_name')
       and not exists (
         select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public, extensions', fn);
  end loop;
end $$;

drop policy if exists "public read avatars" on storage.objects;
drop policy if exists "public read post-images" on storage.objects;
