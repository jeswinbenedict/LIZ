-- ============================================================================
-- Liz — news linking, tightened. Migration 0053. Safe to re-run.
--
-- The first back-fill (0052) made 220 links. Reading all of them, the wrong
-- ones shared a shape: a small launch whose name is an ordinary capitalised
-- word — "Quiet", "Layout", "Worlds", "Misalignment" — matched in a headline
-- written in title case ("The Quiet Weight of Working in Tech").
--
-- A name made only of plain capitalised words now links only when the tool is
-- one Liz's editors added by hand (Claude, Suno, Canva — names people write
-- about by name), or when the article is the tool's own launch post.
-- Distinctive names (ElevenLabs, HN.watch, "Doom or Bloom") are unchanged.
-- ============================================================================

create or replace function public.link_news_item(item_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  linked int;
begin
  insert into news_tools (news_id, tool_id)
  select n.id, t.id
    from news n
    join tools t
      on t.status = 'published'
     and length(t.name) >= 4
     and not ambiguous_tool_name(t.name)
     and n.title ~ ('\m' || regexp_replace(t.name, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '\M')
     and (
       t.name !~ '^[A-Z][a-z]+( [A-Z][a-z]+)*$'
       or t.source = 'curated'
       or n.url in (t.website_url, t.source_url)
     )
   where n.id = item_id
  on conflict do nothing;
  get diagnostics linked = row_count;
  return linked;
end $$;

revoke all on function public.link_news_item(uuid) from public, anon, authenticated;

-- Redo the back-fill under the new rule.
delete from public.news_tools;
select count(*) from (select link_news_item(id) from public.news) backfill;
