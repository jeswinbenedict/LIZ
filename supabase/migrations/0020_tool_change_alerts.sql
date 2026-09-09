-- Make "Follow" mean something.
--
-- The follow button has always promised "we'll notify you of updates", and
-- nothing ever did: the only notification triggers were a reply to your post
-- and someone following you. Following a tool wrote a row and produced silence.
--
-- Two changes are worth interrupting someone for, and both are already stored
-- on `tools`, so neither needs new ingestion:
--
--   * pricing moved — a tool you rely on stopped being free
--   * it broke into the top ten — the "discover it early" case, at the moment
--     it stops being early
--
-- Deliberately not alerted: trend score drifting, description edits, rank
-- moving within the top ten. An alert that fires on noise trains people to
-- ignore the ones that matter.

create or replace function public.on_tool_change_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  follower  record;
  title     text;
  body      text;
  ntype     text;
begin
  -- Only published tools are visible, so only they are worth alerting on.
  if new.status is distinct from 'published'::publish_status then
    return new;
  end if;

  if new.pricing_type is distinct from old.pricing_type
     and old.pricing_type is not null
     and new.pricing_type is not null then
    ntype := 'pricing';
    title := new.name || ' changed its pricing';
    body  := initcap(old.pricing_type::text) || ' is now '
             || initcap(new.pricing_type::text) || '.';
  elsif new.trend_rank is not null
        and new.trend_rank <= 10
        and (old.trend_rank is null or old.trend_rank > 10) then
    ntype := 'trending';
    title := new.name || ' is climbing';
    body  := 'It just entered the top 10 on Liz.';
  else
    return new;
  end if;

  for follower in
    select follower_id
      from public.follows
     where target_type = 'tool'
       and target_id = new.id
  loop
    perform public.notify_user(
      follower.follower_id,
      ntype,
      title,
      body,
      '/tool/' || new.id::text,
      jsonb_build_object('tool_id', new.id)
    );
  end loop;

  return new;
end $$;

drop trigger if exists trg_tool_change_notify on public.tools;

-- Statement-level would be cheaper, but the fan-out needs the old and new row
-- of each change to tell a price move from a rank move.
create trigger trg_tool_change_notify
  after update on public.tools
  for each row
  when (
    old.pricing_type is distinct from new.pricing_type
    or old.trend_rank is distinct from new.trend_rank
  )
  execute function public.on_tool_change_notify();

-- The nightly ranking job rewrites trend_rank for the whole catalog, so the
-- trigger runs once per tool per night, exiting immediately unless a rank
-- actually crossed into the top ten. The fan-out reads follows by
-- (target_type, target_id), which idx_follows_target already covers.
