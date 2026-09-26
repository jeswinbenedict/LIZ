-- ============================================================================
-- Liz — one person, one report. Migration 0034.
--
-- Found while checking whether the unused `report` Edge Function was safe to
-- delete. The app files reports by inserting into `reports` directly, and the
-- handle_report() trigger hides a post, review or comment once it has three
-- open reports. It counted *reports*, not *reporters*, and nothing stopped one
-- person reporting the same thing again.
--
-- Verified against production with two throwaway accounts: one wrote a review,
-- the other reported it three times, and the review went from `active` to
-- `hidden`. Reviews appear on every tool page, so any signed-up user could take
-- down any review they disliked — and with email confirmation off, signing up
-- costs nothing.
--
-- Three changes:
--   1. One report per person per target. A second report from the same person
--      is a no-op, not a vote.
--   2. Auto-hide counts distinct reporters whose accounts are at least a day
--      old. Reports from brand-new accounts are still filed and still reach
--      moderators; they just cannot hide something on their own. This is the
--      part that stands between a stranger and three fresh accounts.
--   3. A reason is capped at 500 characters. The Edge Function did that, but
--      the app never called it, so the cap was not actually applied to
--      anything. It belongs in the table, where no client can skip it.
-- ============================================================================

-- Clear duplicates before the constraint can exist. Keep the earliest report
-- from each person about each thing.
delete from reports r
 using reports earlier
 where r.reporter_id is not null
   and r.reporter_id = earlier.reporter_id
   and r.target_type = earlier.target_type
   and r.target_id   = earlier.target_id
   and (r.created_at, r.id) > (earlier.created_at, earlier.id);

-- A plain unique constraint rather than a partial index, so the client can
-- target it with ON CONFLICT and treat a repeat as success. NULL reporter ids
-- (the reporter later deleted their account) stay distinct, which is right:
-- those reports should not collapse into one.
alter table reports
  drop constraint if exists reports_one_per_reporter;
alter table reports
  add constraint reports_one_per_reporter
  unique (reporter_id, target_type, target_id);

update reports set reason = left(reason, 500) where char_length(reason) > 500;
alter table reports
  drop constraint if exists reports_reason_length;
alter table reports
  add constraint reports_reason_length check (char_length(reason) <= 500);

create or replace function handle_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reporters int;
  threshold constant int := 3;
begin
  -- Distinct people, with accounts old enough that making three of them to
  -- take something down is no longer free. A report from a deleted account
  -- (reporter_id null) does not count toward hiding: nobody is left to stand
  -- behind it.
  select count(distinct r.reporter_id) into reporters
    from reports r
    join profiles p on p.id = r.reporter_id
   where r.target_type = new.target_type
     and r.target_id   = new.target_id
     and r.status      = 'open'
     and p.created_at <= now() - interval '1 day';

  if reporters >= threshold then
    if new.target_type = 'post' then
      update posts set status = 'hidden' where id = new.target_id;
    elsif new.target_type = 'comment' then
      update comments set status = 'hidden' where id = new.target_id;
    elsif new.target_type = 'review' then
      update reviews set status = 'hidden' where id = new.target_id;
    end if;
  end if;
  return null;
end $$;
