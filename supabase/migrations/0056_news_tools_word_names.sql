-- ============================================================================
-- Liz — news linking for tools named after ordinary words. Migration 0056.
-- Safe to re-run.
--
-- 0053 trusted any name an editor added by hand. On 1 October that linked an
-- aviation headline ("NTSB Issues Investigative Update on B-767 Runway
-- Excursion") to Runway, the video model. Several hand-added tools share a
-- name with an everyday word — Runway, Cursor, Perplexity, Mistral, Framer —
-- and for those the headline now has to be about software too: it must also
-- mention AI, a model, an app, a startup, funding, another AI product or a
-- big tech company — or use the name as a possessive ("Perplexity's").
--
-- Bolt and Gamma move here from the outright stop list (0052): with the
-- context rule they can be linked again when the story is about them.
-- ============================================================================

create or replace function public.needs_tech_context(name text)
returns boolean
language sql
immutable
as $$
  select lower(name) = any (array[
    'runway', 'cursor', 'perplexity', 'mistral', 'fireflies', 'framer',
    'jasper', 'bolt', 'gamma', 'notion', 'replay', 'harmony', 'canary'
  ]);
$$;

-- Words that say a headline is about software, as whole words.
create or replace function public.has_tech_context(title text)
returns boolean
language sql
immutable
as $$
  select title ~* ('\m(ai|a\.i\.|llms?|gpt\S*|models?|chatbots?|agents?|agentic|'
                   'startups?|apps?|app store|software|saas|api|sdk|ide|'
                   'coding|code|developers?|generative|genai|text-to-\S+|'
                   'video generator|image generator|copilot|assistant|'
                   'funding|raises|valuation|series [a-e]|open[- ]source|'
                   'tools|citations|chatgpt|claude|codex|gemini|copilot|'
                   'openai|anthropic|google|microsoft|nvidia|meta|amazon|apple)\M');
$$;

-- Bolt and Gamma leave the outright stop list.
create or replace function public.ambiguous_tool_name(name text)
returns boolean
language sql
immutable
as $$
  select lower(name) = any (array[
    'switch', 'ember', 'compute', 'relay', 'raven', 'drift', 'panda', 'seek',
    'wand', 'tiny', 'gaia', 'harden', 'critic', 'natively',
    'twigg', 'pinocchio', 'prodigy', 'solid', 'telos', 'brev',
    'jade', 'kelam', 'keel', 'rig', 'salt', 'mantle',
    'proofrr', 'pen', 'tables', 'minicart', 'reteach', 'decktly', 'margin',
    'tucky', 'cuey', 'bonds', 'clipnote', 'okara', 'scry'
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
     and (
       t.name !~ '^[A-Z][a-z]+( [A-Z][a-z]+)*$'
       or t.source = 'curated'
       or n.url in (t.website_url, t.source_url)
     )
     and (not needs_tech_context(t.name)
          or has_tech_context(n.title)
          -- "Perplexity's", "Cursor’s": a possessive names a company.
          or n.title ~ (regexp_replace(t.name, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '[''’]s\M')
          or n.url in (t.website_url, t.source_url))
   where n.id = item_id
  on conflict do nothing;
  get diagnostics linked = row_count;
  return linked;
end $$;

revoke all on function public.link_news_item(uuid) from public, anon, authenticated;

-- Redo the back-fill under the new rule.
delete from public.news_tools;
select count(*) from (select link_news_item(id) from public.news) backfill;
