-- ============================================================================
-- Liz — the Repository Analyzer's records. Migration 0064. Safe to re-run.
--
-- A person pastes a GitHub address; the analyze-repo function reads the
-- repository and writes one row here with the report, and the files it read
-- (secrets removed) beside it, for Ask to answer from.
--
-- Only the owner of a row can read it. Only the functions (service role)
-- write: a client cannot forge a report or mark someone else's done. A
-- private repository's files are never shared between people; a public one's
-- may be reused by blob SHA, which identifies content, not a person.
-- ============================================================================

create table if not exists public.repo_analyses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  owner        text not null check (length(owner) between 1 and 39),
  repo         text not null check (length(repo) between 1 and 100),
  full_name    text not null,
  ref          text not null,
  commit_sha   text check (commit_sha ~ '^[0-9a-f]{40}$'),
  is_private   boolean not null default false,
  status       text not null default 'queued'
               check (status in ('queued', 'running', 'done', 'failed')),
  stage        text,
  progress     smallint not null default 0 check (progress between 0 and 100),
  error        text,
  error_code   text,
  -- The facts, diagrams and file tree (report) and the written sections
  -- (sections), kept apart so a list of reports never loads either.
  report       jsonb,
  sections     jsonb,
  -- The AI-written overview, when a model was available.
  narrative    jsonb,
  reused_from  uuid references public.repo_analyses(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  finished_at  timestamptz
);

create index if not exists repo_analyses_by_user
  on public.repo_analyses (user_id, created_at desc);
-- "Has anyone analysed this public commit already?"
create index if not exists repo_analyses_public_done
  on public.repo_analyses (full_name, commit_sha)
  where status = 'done' and not is_private;

create table if not exists public.repo_analysis_files (
  analysis_id  uuid not null references public.repo_analyses(id) on delete cascade,
  path         text not null,
  sha          text not null,
  size         integer not null default 0,
  language     text,
  content      text not null,
  primary key (analysis_id, path)
);
-- Reuse of unchanged files between analyses of a public repository.
create index if not exists repo_analysis_files_sha on public.repo_analysis_files (sha);

alter table public.repo_analyses enable row level security;
alter table public.repo_analysis_files enable row level security;

drop policy if exists "read own analyses" on public.repo_analyses;
create policy "read own analyses" on public.repo_analyses
  for select to authenticated using (user_id = current_uid());

drop policy if exists "delete own analyses" on public.repo_analyses;
create policy "delete own analyses" on public.repo_analyses
  for delete to authenticated using (user_id = current_uid());

drop policy if exists "read files of own analyses" on public.repo_analysis_files;
create policy "read files of own analyses" on public.repo_analysis_files
  for select to authenticated using (
    exists (select 1 from public.repo_analyses a
             where a.id = analysis_id and a.user_id = current_uid())
  );

-- No insert or update policy: the functions write with the service role.
revoke insert, update on public.repo_analyses, public.repo_analysis_files from anon, authenticated;
grant select, delete on public.repo_analyses to authenticated;
grant select on public.repo_analysis_files to authenticated;

comment on table public.repo_analyses is
  'One Repository Analyzer run: who asked, which commit, its status and its report.';
comment on table public.repo_analysis_files is
  'Files read by an analysis, secrets removed, for answering questions about it.';

-- ---------------------------------------------------------------------------
-- For the functions only (service role)
-- ---------------------------------------------------------------------------

-- Files already read, by blob SHA: from any public analysis, or from this
-- person's own analyses of the same repository. A private repository's files
-- never reach anyone else.
create or replace function public.repo_known_blobs(shas text[], for_user uuid, for_repo text)
returns table (sha text, content text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (f.sha) f.sha, f.content
    from repo_analysis_files f
    join repo_analyses a on a.id = f.analysis_id
   where f.sha = any(shas)
     and a.status = 'done'
     and (not a.is_private or (a.user_id = for_user and a.full_name = for_repo));
$$;

-- A finished public analysis of the same commit, copied for another person
-- instead of read again.
create or replace function public.copy_repo_analysis(source uuid, for_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  fresh uuid;
begin
  insert into repo_analyses (user_id, owner, repo, full_name, ref, commit_sha, is_private,
                             status, stage, progress, report, sections, narrative,
                             reused_from, finished_at)
  select for_user, owner, repo, full_name, ref, commit_sha, false,
         'done', 'Reused an earlier analysis of this commit', 100, report, sections, narrative,
         id, now()
    from repo_analyses
   where id = source and status = 'done' and not is_private
  returning id into fresh;
  if fresh is null then
    return null;
  end if;
  insert into repo_analysis_files (analysis_id, path, sha, size, language, content)
  select fresh, path, sha, size, language, content from repo_analysis_files where analysis_id = source;
  return fresh;
end $$;

revoke all on function public.repo_known_blobs(text[], uuid, text) from public, anon, authenticated;
revoke all on function public.copy_repo_analysis(uuid, uuid) from public, anon, authenticated;
grant execute on function public.repo_known_blobs(text[], uuid, text) to service_role;
grant execute on function public.copy_repo_analysis(uuid, uuid) to service_role;
