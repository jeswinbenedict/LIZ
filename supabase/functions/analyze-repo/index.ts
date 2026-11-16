// POST /analyze-repo — the Repository Analyzer.
//
// Body: { "url": "https://github.com/owner/name", "ref": "main"?, "token": "…"? }
//   → { data: { id, cached }, error }  and the analysis runs in the background,
//     writing its progress and then its report to repo_analyses.
// Body: { "url": "…", "action": "branches", "token"? }
//   → { data: { defaultBranch, branches, private }, error }
//
// Signed-in people only, ten analyses an hour each. The repository and commit
// are resolved before answering, so a wrong address, a private repository
// without a token, or GitHub's limit is told at once. A public commit someone
// already analysed is copied rather than read again; files whose content was
// read before (same Git blob) are not fetched twice.
//
// A token is used for this run only: it is not stored, logged or returned.
// Repository content is never executed (see _shared/repo/pipeline.ts).
//
// Deploy: supabase functions deploy analyze-repo

import { json, corsHeaders } from '../_shared/cors.ts';
import { callerKey, tooManyRequests, withinRateLimit } from '../_shared/rate_limit.ts';
import { GitHub, GitHubError } from '../_shared/repo/github.ts';
import { cleanRef, parseRepoUrl } from '../_shared/repo/url.ts';
import { factsForAi, resolve, runAnalysis } from '../_shared/repo/pipeline.ts';
import { narrate } from '../_shared/repo/narrate.ts';
import { admin, cleanToken, githubFailure, lizUid } from '../_shared/repo/caller.ts';

const ANALYSES_PER_HOUR = 10;
const REUSE_DAYS = 30;
/// A run whose row has not moved for this long was stopped by the platform.
const STALE_MINUTES = 6;

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ data: null, error: 'Use POST' }, 405);

  const db = admin();
  const uid = await lizUid(req, db);
  if (!uid) return json({ data: null, error: 'Sign in to analyse a repository' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ data: null, error: 'Send JSON' }, 400);
  }
  const where = parseRepoUrl(String(body.url ?? ''));
  if (!where) return json({ data: null, error: 'That is not a GitHub repository address. Paste one like https://github.com/owner/name.', code: 'bad_url' }, 400);
  const token = cleanToken(body.token);
  if (token === undefined) return json({ data: null, error: 'That does not look like a GitHub token.', code: 'bad_token' }, 400);
  const askedRef = body.ref == null || body.ref === '' ? where.ref ?? null : cleanRef(body.ref);
  if (askedRef === null && body.ref) return json({ data: null, error: 'That branch name is not valid.', code: 'bad_ref' }, 400);

  const gh = new GitHub(token);

  if (body.action === 'branches') {
    try {
      const info = await gh.repo(where.owner, where.repo);
      const branches = await gh.branches(where.owner, where.repo);
      const ordered = [info.defaultBranch, ...branches.filter((b) => b !== info.defaultBranch)];
      return json({ data: { fullName: info.fullName, defaultBranch: info.defaultBranch, branches: ordered, private: info.private }, error: null });
    } catch (e) {
      if (e instanceof GitHubError) return githubFailure(e);
      return json({ data: null, error: 'Could not reach GitHub.' }, 502);
    }
  }

  if (!(await withinRateLimit(`analyze-repo:${uid}`, ANALYSES_PER_HOUR)) || !(await withinRateLimit(callerKey(req, 'analyze-repo'), ANALYSES_PER_HOUR * 3))) {
    return tooManyRequests(900);
  }

  let resolved;
  try {
    resolved = await resolve(gh, where.owner, where.repo, askedRef ?? null);
  } catch (e) {
    if (e instanceof GitHubError) return githubFailure(e);
    return json({ data: null, error: 'Could not reach GitHub.' }, 502);
  }
  const { info, ref, commit } = resolved;

  // Runs the platform stopped (time limit, restart) never wrote their end.
  await db.from('repo_analyses').update({ status: 'failed', error: 'The analysis was stopped before it finished. Try again.', error_code: 'stopped' })
    .eq('user_id', uid).in('status', ['queued', 'running']).lt('updated_at', new Date(Date.now() - STALE_MINUTES * 60_000).toISOString());

  // The same commit, already running for this person: follow that one.
  const { data: running } = await db.from('repo_analyses').select('id').eq('user_id', uid).eq('full_name', info.fullName)
    .eq('commit_sha', commit.sha).in('status', ['queued', 'running']).limit(1).maybeSingle();
  if (running) return json({ data: { id: running.id, cached: false }, error: null });

  // The same public commit, done before by anyone: copy it.
  if (!info.private) {
    const since = new Date(Date.now() - REUSE_DAYS * 86_400_000).toISOString();
    const { data: prior } = await db.from('repo_analyses').select('id').eq('full_name', info.fullName).eq('commit_sha', commit.sha)
      .eq('status', 'done').eq('is_private', false).gte('finished_at', since).order('finished_at', { ascending: false }).limit(1).maybeSingle();
    if (prior) {
      const { data: copied } = await db.rpc('copy_repo_analysis', { source: prior.id, for_user: uid });
      if (copied) return json({ data: { id: copied, cached: true }, error: null });
    }
  }

  const [owner, repo] = info.fullName.split('/');
  const { data: row, error } = await db.from('repo_analyses').insert({
    user_id: uid, owner, repo, full_name: info.fullName, ref, commit_sha: commit.sha, is_private: info.private,
    status: 'running', stage: 'Starting', progress: 5,
  }).select('id').single();
  if (error || !row) return json({ data: null, error: 'Could not start the analysis.' }, 500);
  const id = row.id as string;

  const job = (async () => {
    const touch = (patch: Record<string, unknown>) => db.from('repo_analyses').update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id);
    try {
      const result = await runAnalysis(gh, owner, repo, resolved, {
        progress: async (stage, progress) => { await touch({ stage, progress }); },
        knownBlobs: async (shas) => {
          const { data } = await db.rpc('repo_known_blobs', { shas, for_user: uid, for_repo: info.fullName });
          return new Map(((data ?? []) as { sha: string; content: string }[]).map((r) => [r.sha, r.content]));
        },
      });
      await touch({ stage: 'Saving files', progress: 88 });
      for (let i = 0; i < result.files.length; i += 40) {
        const batch = result.files.slice(i, i + 40).map((f) => ({ analysis_id: id, ...f }));
        const { error: e } = await db.from('repo_analysis_files').upsert(batch);
        if (e) throw new Error(`Could not save files: ${e.message}`);
      }
      await touch({ stage: 'Writing the overview', progress: 93 });
      let narrative = null;
      try {
        narrative = await narrate(factsForAi(result.report, result.sections));
      } catch (_) {
        // No model, or its key refused: the report stands without prose.
      }
      await touch({ status: 'done', stage: 'Done', progress: 100, report: result.report, sections: result.sections, narrative, finished_at: new Date().toISOString() });
    } catch (e) {
      const known = e instanceof GitHubError;
      await touch({ status: 'failed', error: known ? e.message : 'The analysis failed. Try again in a minute.', error_code: known ? e.code : 'failed' });
      if (!known) console.error('analyze-repo failed', id, e instanceof Error ? e.message : String(e));
    }
  })();

  if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(job);
  else await job;
  return json({ data: { id, cached: false }, error: null }, 202);
});
