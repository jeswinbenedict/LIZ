-- Don't call it a price change when the catalog simply learned the price.
--
-- Most scraped tools land as `unknown` and get a real pricing_type once a
-- later pass reads the product's pricing page. Under 0020 that produced
-- "Unknown is now Free." — which is not something happening to the product,
-- it is Liz catching up, and it is not worth interrupting anyone for. Tested
-- against the live trigger, which duly sent exactly that.
--
-- Only a move between two known prices is a real change.

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
  if new.status is distinct from 'published'::publish_status then
    return new;
  end if;

  if new.pricing_type is distinct from old.pricing_type
     and old.pricing_type is not null
     and new.pricing_type is not null
     and old.pricing_type <> 'unknown'::pricing_type
     and new.pricing_type <> 'unknown'::pricing_type then
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
