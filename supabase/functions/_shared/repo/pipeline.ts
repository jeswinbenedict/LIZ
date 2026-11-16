// One analysis, start to finish, with the network and storage passed in.
//
// resolve → list the tree → choose files → read them (re-using any file whose
// Git blob was already read in an earlier analysis: a blob's SHA is its
// content, so an unchanged file is never fetched twice) → redact secrets →
// extract facts → draw the architecture → write the report.
//
// Repository content is data from a stranger. It is parsed with patterns and
// never executed, imported or evaluated; nothing in it changes what this code
// does. The AI pass (narrate) sees the facts this code extracted, and the
// README only inside a block it is told is untrusted.

import { GitHub, GitHubError, type RepoInfo, type TreeEntry } from './github.ts';
import { selectFiles, isLockfile, inSkippedDir, isSecretFile } from './select.ts';
import { redact, type SecretFinding } from './secrets.ts';
import { detectTech, languageOf, parseManifests } from './detect.ts';
import {
  extractContainers, extractDeployment, extractEndpoints, extractEntryPoints, extractEnv,
  extractImports, extractQuality, extractSchema, extractWorkflows,
} from './extract.ts';
import { buildGraphs, buildModules } from './architecture.ts';
import { buildReport, type Section } from './report.ts';

export interface StoredFile {
  path: string;
  sha: string;
  size: number;
  language: string | null;
  content: string;
}

export interface AnalysisResult {
  info: RepoInfo;
  ref: string;
  commit: { sha: string; date: string | null; message: string };
  report: Record<string, unknown>;
  sections: Section[];
  files: StoredFile[];
}

export interface PipelineIO {
  progress: (stage: string, percent: number) => Promise<void>;
  /** Contents of blobs an earlier analysis already read, by SHA (one call). */
  knownBlobs?: (shas: string[]) => Promise<Map<string, string>>;
}

const CONCURRENCY = 10;

/// What a repository and ref resolve to, before any work is queued: done in
/// the request itself, so a wrong address or a missing token is answered at
/// once rather than as a failed job.
export async function resolve(gh: GitHub, owner: string, repo: string, ref: string | null) {
  const info = await gh.repo(owner, repo);
  const use = ref ?? info.defaultBranch;
  const commit = await gh.commit(owner, repo, use);
  return { info, ref: use, commit };
}

export async function runAnalysis(
  gh: GitHub,
  owner: string,
  repo: string,
  resolved: { info: RepoInfo; ref: string; commit: { sha: string; date: string | null; message: string } },
  io: PipelineIO,
): Promise<AnalysisResult> {
  const started = Date.now();
  const { info, ref, commit } = resolved;

  await io.progress('Listing files', 10);
  const [{ entries, truncated }, languages] = await Promise.all([gh.tree(owner, repo, commit.sha), gh.languages(owner, repo)]);
  const blobs = entries.filter((e) => e.type === 'blob');
  if (blobs.length === 0) throw new GitHubError('This repository has no files at that commit.', 'not_found');
  const paths = blobs.map((e) => e.path);
  const chosen = selectFiles(blobs);

  await io.progress(`Reading ${chosen.length} files`, 18);
  const known = io.knownBlobs ? await io.knownBlobs(chosen.map((e) => e.sha)).catch(() => new Map<string, string>()) : new Map<string, string>();
  const files = new Map<string, string>();
  const stored: StoredFile[] = [];
  const skipped: { path: string; reason: string }[] = [];
  const secrets: SecretFinding[] = [];
  let cachedFiles = 0;
  let done = 0;
  const queue = [...chosen];
  const worker = async () => {
    while (queue.length) {
      const e = queue.shift()!;
      try {
        let text = known.get(e.sha) ?? null;
        if (text != null) cachedFiles++;
        else text = await gh.text(owner, repo, commit.sha, e.path);
        if (text.includes('\u0000')) {
          skipped.push({ path: e.path, reason: 'binary' });
          continue;
        }
        const clean = redact(e.path, text);
        secrets.push(...clean.findings);
        files.set(e.path, clean.text);
        stored.push({ path: e.path, sha: e.sha, size: e.size ?? clean.text.length, language: languageOf(e.path), content: clean.text });
      } catch (err) {
        if (err instanceof GitHubError && err.code === 'rate_limited') throw err;
        skipped.push({ path: e.path, reason: 'could not be read' });
      } finally {
        done++;
        if (done % 15 === 0) await io.progress(`Reading files (${done}/${chosen.length})`, 18 + Math.round((done / chosen.length) * 50));
      }
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  await io.progress('Finding the stack and architecture', 72);
  const { deps, scripts } = parseManifests(files);
  const techs = detectTech(paths, files, deps);
  const endpoints = extractEndpoints(files);
  const { entities, relations } = extractSchema(files);
  const env = extractEnv(files);
  const workflows = extractWorkflows(files);
  const containers = extractContainers(files);
  const deploy = extractDeployment(files, paths);
  const entryPoints = extractEntryPoints(files, paths);
  const pathSet = new Set(paths);
  const imports = extractImports(files, pathSet);
  const modules = buildModules(paths.filter((p) => !inSkippedDir(p)), languageOf, imports);
  const lockfiles = paths.filter(isLockfile);
  const quality = extractQuality(files, paths, lockfiles);
  const committedEnvFiles = paths.filter((p) => isSecretFile(p) && /(^|\/)\.env(\.|$)/.test(p));

  await io.progress('Drawing diagrams', 82);
  const graphs = buildGraphs({ techs, deps, endpoints, entities, relations, workflows, deploy, entryPoints, modules, files });
  const readmePath = paths.find((p) => /^README(\.md|\.markdown|\.rst|\.txt)?$/i.test(p));
  const sections = buildReport({
    repo: info, ref, commit, languages, paths, readFiles: files.size, truncated,
    readme: readmePath ? files.get(readmePath) ?? null : null,
    techs, deps, scripts, endpoints, entities, relations, env, workflows, containers, deploy, entryPoints,
    modules, graphs, quality, secrets, committedEnvFiles,
  });

  const read = new Set(files.keys());
  const tree = blobs.slice(0, 8000).map((e: TreeEntry) => ({ p: e.path, s: e.size ?? 0, r: read.has(e.path) ? 1 : 0 }));

  return {
    info, ref, commit, sections,
    files: stored,
    report: {
      version: 1,
      repo: info,
      ref,
      commit,
      languages,
      tree,
      treeTruncated: truncated || blobs.length > 8000,
      techs,
      dependencies: deps.slice(0, 400),
      scripts,
      endpoints,
      entities,
      relations,
      env: env.map((e) => ({ name: e.name, documented: e.documented, refs: e.refs })),
      workflows,
      containers,
      deploy,
      entryPoints,
      modules,
      graphs,
      quality,
      secrets,
      stats: {
        files: blobs.length,
        read: files.size,
        reused: cachedFiles,
        skipped: skipped.slice(0, 100),
        apiCalls: gh.calls,
        authenticated: gh.authenticated,
        ms: Date.now() - started,
      },
    },
  };
}

/// Facts the AI may write from: what this code extracted, compact. Raw source
/// is not included, so an instruction hidden in a file has no way in.
export function factsForAi(report: Record<string, unknown>, sections: Section[]): string {
  const r = report as Record<string, any>;
  return JSON.stringify({
    repository: r.repo?.fullName,
    description: r.repo?.description,
    languages: r.languages,
    technologies: (r.techs ?? []).map((t: any) => `${t.name} (${t.category}, ${t.confidence})`),
    modules: (r.modules ?? []).slice(0, 20).map((m: any) => `${m.path}: ${m.role}, ${m.files} files`),
    endpoints: (r.endpoints ?? []).slice(0, 30).map((e: any) => `${e.method} ${e.route}`),
    tables: (r.entities ?? []).slice(0, 25).map((e: any) => e.name),
    deployment: [...new Set((r.deploy ?? []).map((d: any) => d.platform))],
    workflows: (r.workflows ?? []).map((w: any) => w.name),
    quality: r.quality,
    findings: sections.find((s) => s.id === 'improvements')?.items.map((i) => i.label),
  });
}
