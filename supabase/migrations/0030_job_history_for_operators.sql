-- Let an operator holding the service role read the job history.
--
-- recent_job_runs() was moderator-only, which meant it could only be read from
-- inside the app while signed in as an admin. That is the wrong shape for a
-- diagnostic: the moment worth reading it is when something scheduled has
-- stopped, and the person checking is usually holding a service key and a
-- terminal, not a browser session.
--
-- The service role already bypasses RLS on every table; letting it read job
-- metadata widens nothing.
create or replace function recent_job_runs(limit_count int default 20)
returns table (
  job_name   text,
  status     text,
  started_at timestamptz,
  duration_s numeric,
  message    text
)
language sql
stable
security definer
set search_path = public, cron
as $$
  select
    j.jobname::text,
    d.status::text,
    d.start_time,
    round(extract(epoch from (d.end_time - d.start_time))::numeric, 2),
    left(coalesce(d.return_message, ''), 200)
  from cron.job_run_details d
  join cron.job j on j.jobid = d.jobid
  where is_moderator()
     or coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')
        = 'service_role'
  order by d.start_time desc
  limit greatest(limit_count, 1);
$$;

grant execute on function recent_job_runs(int) to authenticated, service_role;
