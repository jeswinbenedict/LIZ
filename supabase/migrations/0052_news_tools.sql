-- ============================================================================
-- Liz — news linked to the tools it mentions. Migration 0052. Safe to re-run.
--
-- News (4,800 articles) and the catalog were two products side by side: an
-- article about ElevenLabs' valuation never appeared on ElevenLabs' page. Each
-- article is now matched against tool names when it arrives, and a tool page
-- shows the articles that name it.
--
-- Matching is deliberately conservative, because a wrong link is worse than
-- none. Measured against 3,000 recent headlines (1 Oct 2026): a plain match
-- linked "Switch" to a Nintendo controller review, "Ember" to a coffee mug and
-- "serve" to "self-serve". So:
--   * case-sensitive, on word boundaries, in the headline only;
--   * names under four characters are skipped;
--   * a name that is one all-lowercase word is skipped ("serve", "cli");
--   * names that are also everyday words are on a stop list.
-- ============================================================================

create table if not exists public.news_tools (
  news_id uuid not null references public.news(id) on delete cascade,
  tool_id uuid not null references public.tools(id) on delete cascade,
  primary key (news_id, tool_id)
);

create index if not exists idx_news_tools_tool on public.news_tools (tool_id);

alter table public.news_tools enable row level security;
drop policy if exists "read links between published rows" on public.news_tools;
create policy "read links between published rows" on public.news_tools
  for select using (
    exists (select 1 from public.news n where n.id = news_id and n.status = 'published')
    and exists (select 1 from public.tools t where t.id = tool_id and t.status = 'published')
  );

-- Names that are also everyday words, so a headline using the word is not
-- about the tool. Lower case; extend as the catalog grows.
create or replace function public.ambiguous_tool_name(name text)
returns boolean
language sql
immutable
as $$
  select lower(name) = any (array[
    'switch', 'ember', 'compute', 'relay', 'raven', 'drift', 'panda', 'seek',
    'wand', 'tiny', 'gaia', 'bolt', 'harden', 'critic', 'natively', 'replay',
    'twigg', 'pinocchio', 'prodigy', 'compute', 'solid', 'telos', 'brev',
    'jade', 'harmony', 'kelam', 'canary', 'keel', 'rig', 'salt', 'mantle',
    'proofrr', 'pen', 'tables', 'minicart', 'reteach', 'decktly', 'margin',
    'tucky', 'cuey', 'bonds', 'clipnote', 'okara', 'scry', 'gamma'
  ])
  or (name ~ '^[a-z]+$');
$$;

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
   where n.id = item_id
  on conflict do nothing;
  get diagnostics linked = row_count;
  return linked;
end $$;

revoke all on function public.link_news_item(uuid) from public, anon, authenticated;

create or replace function public.on_news_insert_link()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform link_news_item(new.id);
  return new;
end $$;

drop trigger if exists trg_news_link_tools on public.news;
create trigger trg_news_link_tools
  after insert on public.news
  for each row execute function public.on_news_insert_link();

-- Back-fill what is already there.
select count(*) from (select link_news_item(id) from public.news) backfill;
