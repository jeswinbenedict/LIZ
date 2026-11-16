// The report: twenty-three sections, each written from the facts found.
//
// A section is a summary sentence and a list of items, every item with the
// paths it came from. Where the analysis found nothing for a section, the
// section says so plainly ("No database schema was found") rather than
// guessing: an honest gap is more useful than a confident invention.

import type { Dependency, Tech } from './detect.ts';
import { purposeOf } from './detect.ts';
import type { Container, DeployTarget, Endpoint, Entity, EnvVar, Quality, Ref, Relation, Workflow } from './extract.ts';
import type { Graph, Module } from './architecture.ts';
import type { RepoInfo } from './github.ts';
import type { SecretFinding } from './secrets.ts';

export interface Item {
  label: string;
  value?: string;
  refs?: string[];
}

export interface Section {
  id: string;
  title: string;
  summary: string;
  items: Item[];
  graphs?: string[];
}

export interface ReportInput {
  repo: RepoInfo;
  ref: string;
  commit: { sha: string; date: string | null; message: string };
  languages: Record<string, number>;
  paths: string[];
  readFiles: number;
  truncated: boolean;
  readme: string | null;
  techs: Tech[];
  deps: Dependency[];
  scripts: Record<string, Record<string, string>>;
  endpoints: Endpoint[];
  entities: Entity[];
  relations: Relation[];
  env: EnvVar[];
  workflows: Workflow[];
  containers: Container[];
  deploy: DeployTarget[];
  entryPoints: Ref[];
  modules: Module[];
  graphs: Graph[];
  quality: Quality;
  secrets: SecretFinding[];
  committedEnvFiles: string[];
}

const at = (r: Ref) => `${r.path}:${r.line}`;
const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;
const list = (xs: string[], max = 6) => (xs.length > max ? `${xs.slice(0, max).join(', ')} and ${xs.length - max} more` : xs.join(', '));
const byCat = (t: Tech[], ...c: string[]) => t.filter((x) => c.includes(x.category));
const techItem = (t: Tech): Item => ({ label: t.name, value: `${t.purpose}${t.confidence === 'inferred' ? ' (inferred from code, not a declared dependency)' : ''}`, refs: t.evidence });

/// The first paragraph of the README that reads as prose, plain text.
export function readmeIntro(md: string | null): string | null {
  if (!md) return null;
  const text = md
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/```[\s\S]*?```/g, '')
    .replace(/<[^>]+>/g, ' ');
  for (const block of text.split(/\n\s*\n/)) {
    const b = block.trim();
    if (!b || /^#|^\[!\[|^!\[|^\||^[-*] |^>\s*\[!|^---/.test(b)) continue;
    const plain = b.replace(/!\[[^\]]*\]\([^)]*\)/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/[*_`]/g, '').replace(/\s+/g, ' ').trim();
    if (plain.length >= 40) return plain.slice(0, 600);
  }
  return null;
}

export function buildReport(r: ReportInput): Section[] {
  const s: Section[] = [];
  const t = r.techs;
  const prodDeps = r.deps.filter((d) => !d.dev);
  const devDeps = r.deps.filter((d) => d.dev);
  const front = byCat(t, 'Frontend', 'Mobile', 'Desktop');
  const back = byCat(t, 'Backend', 'Backend-as-a-service');
  const dbs = byCat(t, 'Database', 'ORM');
  const auth = byCat(t, 'Auth');
  const langTotal = Object.values(r.languages).reduce((a, b) => a + b, 0) || 1;
  const langs = Object.entries(r.languages).sort((a, b) => b[1] - a[1]);
  const has = (id: string) => r.graphs.some((g) => g.id === id);

  // 1
  s.push({
    id: 'overview', title: 'Repository overview',
    summary: `${r.repo.fullName} at ${r.ref} (${r.commit.sha.slice(0, 7)}${r.commit.date ? `, ${r.commit.date.slice(0, 10)}` : ''}): ${plural(r.paths.length, 'file')}, ${plural(r.readFiles, 'file')} read for this report.${r.truncated ? ' GitHub truncated the file list for this repository, so the largest folders may be incomplete.' : ''}`,
    items: [
      { label: 'Visibility', value: r.repo.private ? 'Private' : 'Public' },
      { label: 'Default branch', value: r.repo.defaultBranch },
      { label: 'Latest commit', value: r.commit.message || r.commit.sha.slice(0, 7) },
      { label: 'Stars · forks · open issues', value: `${r.repo.stars} · ${r.repo.forks} · ${r.repo.openIssues}` },
      ...(r.repo.license ? [{ label: 'License', value: r.repo.license }] : []),
      ...(r.repo.homepage ? [{ label: 'Website', value: r.repo.homepage }] : []),
      ...(r.repo.topics.length ? [{ label: 'Topics', value: r.repo.topics.join(', ') }] : []),
      ...(r.repo.archived ? [{ label: 'Archived', value: 'Yes: read-only, no longer maintained' }] : []),
    ],
  });

  // 2
  const intro = readmeIntro(r.readme);
  s.push({
    id: 'description', title: 'Project description',
    summary: r.repo.description ?? intro ?? 'The repository has no description and no README introduction.',
    items: intro && r.repo.description ? [{ label: 'From the README', value: intro, refs: ['README.md'] }] : [],
  });

  // 3
  s.push({
    id: 'stack', title: 'Technology stack',
    summary: t.length ? `${plural(t.filter((x) => x.confidence === 'confirmed').length, 'technology', 'technologies')} confirmed by dependencies or configuration, ${t.filter((x) => x.confidence === 'inferred').length} inferred from code.` : 'No known framework or service was found in the manifests or configuration.',
    items: t.map((x) => ({ label: `${x.name} · ${x.category}`, value: `${x.purpose}${x.confidence === 'inferred' ? ' (inferred)' : ''}`, refs: x.evidence })),
  });

  // 4
  s.push({
    id: 'languages', title: 'Programming languages',
    summary: langs.length ? `Mostly ${langs[0][0]} (${Math.round((langs[0][1] / langTotal) * 100)}% of the code, by GitHub's count).` : 'GitHub reported no languages for this repository.',
    items: langs.slice(0, 12).map(([l, b]) => ({ label: l, value: `${((b / langTotal) * 100).toFixed(1)}%` })),
  });

  // 5
  const top = new Map<string, number>();
  for (const p of r.paths) {
    const k = p.includes('/') ? `${p.split('/')[0]}/` : p;
    top.set(k, (top.get(k) ?? 0) + 1);
  }
  s.push({
    id: 'structure', title: 'Repository structure',
    summary: `${plural([...top.keys()].filter((k) => k.endsWith('/')).length, 'top-level folder')} and ${plural([...top.keys()].filter((k) => !k.endsWith('/')).length, 'top-level file')}. Entry points: ${r.entryPoints.length ? list(r.entryPoints.map((e) => e.path), 4) : 'none identified'}.`,
    items: [
      ...r.modules.slice(0, 16).map((m) => ({ label: m.path, value: `${m.role} · ${plural(m.files, 'file')}${m.languages.length ? ` · ${m.languages.join(', ')}` : ''}`, refs: m.keyFiles.slice(0, 3) })),
      ...r.entryPoints.slice(0, 6).map((e) => ({ label: `Entry point: ${e.path}`, refs: [at(e)] })),
    ],
  });

  // 6
  const sys = r.graphs.find((g) => g.id === 'system');
  s.push({
    id: 'architecture', title: 'System architecture',
    summary: sys
      ? `${front.length ? `A ${list(front.map((x) => x.name), 3)} front end` : 'No front end'}${back.length ? `, a back end on ${list(back.map((x) => x.name), 3)}` : r.endpoints.length ? ', server routes' : ', no separate back end'}${dbs.length ? `, data in ${list(dbs.map((x) => x.name), 3)}` : ''}${r.deploy.length ? `, deployed to ${list([...new Set(r.deploy.map((d) => d.platform))], 3)}` : ''}.`
      : 'Not enough was found to draw the system: no framework, server or data store was identified.',
    items: sys ? sys.edges.map((e) => ({ label: `${sys.nodes.find((n) => n.id === e.from)?.label.split('\n')[0]} → ${sys.nodes.find((n) => n.id === e.to)?.label.split('\n')[0]}`, value: e.label })) : [],
    graphs: has('system') ? ['system'] : [],
  });

  // 7
  const uiMods = r.modules.filter((m) => /UI|Pages|screens|feature|state|hooks|Styles/i.test(m.role));
  s.push({
    id: 'frontend', title: 'Frontend architecture',
    summary: front.length ? `${list(front.map((x) => x.name))}${byCat(t, 'State management').length ? `, with state in ${list(byCat(t, 'State management').map((x) => x.name))}` : ''}${byCat(t, 'Routing').length ? `, routing by ${list(byCat(t, 'Routing').map((x) => x.name))}` : ''}${byCat(t, 'Styling').length ? `, styled with ${list(byCat(t, 'Styling').map((x) => x.name))}` : ''}.` : 'No front-end framework was found.',
    items: [...front, ...byCat(t, 'State management', 'Routing', 'Styling')].map(techItem).concat(uiMods.slice(0, 10).map((m) => ({ label: m.path, value: m.role, refs: m.keyFiles.slice(0, 3) }))),
  });

  // 8
  const apiMods = r.modules.filter((m) => /API|Serverless|Business|Background|middleware|shared between server/i.test(m.role));
  s.push({
    id: 'backend', title: 'Backend architecture',
    summary: back.length || r.endpoints.length ? `${back.length ? list(back.map((x) => x.name)) : 'Server code'} serving ${plural(r.endpoints.length, 'route')}${byCat(t, 'Messaging').length ? `, with background work on ${list(byCat(t, 'Messaging').map((x) => x.name))}` : ''}.` : 'No back-end framework or server routes were found; this may be a front-end-only project, a library or a tool.',
    items: [...back, ...byCat(t, 'Messaging', 'Realtime', 'API')].map(techItem).concat(apiMods.slice(0, 10).map((m) => ({ label: m.path, value: m.role, refs: m.keyFiles.slice(0, 3) }))),
  });

  // 9
  s.push({
    id: 'database', title: 'Database architecture',
    summary: r.entities.length ? `${plural(r.entities.length, 'table or model', 'tables or models')} and ${plural(r.relations.length, 'relationship')}, read from ${list([...new Set(r.entities.map((e) => e.source))])}${dbs.length ? `, on ${list(dbs.map((x) => x.name))}` : ''}.` : dbs.length ? `${list(dbs.map((x) => x.name))} is used, but no schema was found in the files read.` : 'No database schema or database dependency was found.',
    items: [...dbs.map(techItem), ...r.entities.slice(0, 40).map((e) => ({ label: `${e.name} (${e.source})`, value: e.columns.slice(0, 10).map((c) => c.name).join(', ') || undefined, refs: [at(e)] }))],
    graphs: has('database') ? ['database'] : [],
  });

  // 10
  s.push({
    id: 'api', title: 'API documentation',
    summary: r.endpoints.length ? `${plural(r.endpoints.length, 'route')} declared in code, by ${list([...new Set(r.endpoints.map((e) => e.framework.split(' →')[0]))])}.` : 'No API route declarations were found.',
    items: r.endpoints.slice(0, 120).map((e) => ({ label: `${e.method} ${e.route}`, value: e.framework, refs: [at(e)] })),
    graphs: has('api') ? ['api'] : [],
  });

  // 11
  s.push({
    id: 'auth', title: 'Authentication and authorization',
    summary: auth.length ? `Sign-in through ${list(auth.map((x) => x.name))}.` : 'No authentication library or provider was found.',
    items: auth.map(techItem),
    graphs: has('auth') ? ['auth'] : [],
  });

  // 12
  s.push({
    id: 'modules', title: 'Important modules and components',
    summary: `${plural(r.modules.length, 'module')}, the largest first. Key files are the ones most imported by the rest.`,
    items: r.modules.slice(0, 24).map((m) => ({ label: m.path, value: `${m.role}. ${plural(m.files, 'file')}.${m.imports.length ? ` Uses ${list(m.imports, 4)}.` : ''}${m.importedBy.length ? ` Used by ${list(m.importedBy, 4)}.` : ''}`, refs: m.keyFiles.slice(0, 4) })),
    graphs: has('modules') ? ['modules'] : [],
  });

  // 13
  s.push({
    id: 'dependencies', title: 'Dependencies and libraries',
    summary: r.deps.length ? `${plural(prodDeps.length, 'runtime dependency', 'runtime dependencies')} and ${plural(devDeps.length, 'development dependency', 'development dependencies')} across ${plural(new Set(r.deps.map((d) => d.manifest)).size, 'manifest')}${r.quality.lockfiles.length ? `; versions locked by ${list(r.quality.lockfiles, 3)}` : '; no lock file, so installs may resolve different versions over time'}.` : 'No dependency manifest was found.',
    items: [...prodDeps, ...devDeps].slice(0, 150).map((d) => ({ label: `${d.name}${d.dev ? ' (dev)' : ''}`, value: `${d.version} · ${d.ecosystem}${purposeOf(d) ? ` · ${purposeOf(d)}` : ''}`, refs: [d.manifest] })),
  });

  // 14
  const flow: Item[] = [];
  if (r.entryPoints.length) flow.push({ label: 'Starts at', value: list(r.entryPoints.map((e) => e.path), 3), refs: r.entryPoints.slice(0, 3).map(at) });
  if (front.length) flow.push({ label: 'The interface', value: `${list(front.map((x) => x.name), 2)} renders the screens${byCat(t, 'Routing').length ? ` and ${byCat(t, 'Routing')[0].name} moves between them` : ''}.` });
  if (r.endpoints.length) flow.push({ label: 'Requests', value: `go to ${plural(r.endpoints.length, 'route')} (${list([...new Set(r.endpoints.map((e) => e.route.split('/').filter(Boolean)[0] ?? '/'))], 5)}).`, refs: r.endpoints.slice(0, 3).map(at) });
  if (dbs.length) flow.push({ label: 'Data', value: `is kept in ${list(dbs.map((x) => x.name), 3)}.` });
  if (byCat(t, 'Messaging').length || r.workflows.some((w) => w.triggers.includes('schedule'))) flow.push({ label: 'In the background', value: `${list([...byCat(t, 'Messaging').map((x) => x.name), ...r.workflows.filter((w) => w.triggers.includes('schedule')).map((w) => `scheduled workflow “${w.name}”`)], 4)}.` });
  s.push({ id: 'workflow', title: 'Application workflow', summary: flow.length ? 'How a run of the application proceeds, from what was found.' : 'Not enough was found to describe a run of the application.', items: flow });

  // 15
  const dataFlow: Item[] = [];
  const sysG = r.graphs.find((g) => g.id === 'system');
  if (sysG) for (const e of sysG.edges) dataFlow.push({ label: `${sysG.nodes.find((n) => n.id === e.from)?.label.split('\n')[0]} → ${sysG.nodes.find((n) => n.id === e.to)?.label.split('\n')[0]}`, value: e.label, refs: sysG.nodes.find((n) => n.id === e.to)?.refs?.slice(0, 2) });
  s.push({ id: 'dataflow', title: 'Data flow', summary: dataFlow.length ? 'Where data moves between the parts of the system.' : 'No data movement between parts could be established.', items: dataFlow, graphs: has('system') ? ['system'] : [] });

  // 16
  const build: Item[] = [];
  for (const [manifest, sc] of Object.entries(r.scripts)) {
    for (const [name, cmd] of Object.entries(sc).slice(0, 14)) build.push({ label: `${manifest.endsWith('deno.json') || manifest.endsWith('deno.jsonc') ? 'deno task' : 'npm run'} ${name}`, value: String(cmd).slice(0, 160), refs: [manifest] });
  }
  if (t.some((x) => x.name === 'Flutter')) build.push({ label: 'flutter pub get, then flutter run', value: 'Install packages and run the app (Flutter)', refs: ['pubspec.yaml'] });
  if (r.deps.some((d) => d.ecosystem === 'pypi')) build.push({ label: 'pip install -r requirements.txt (or the pyproject tool)', value: 'Install the Python dependencies', refs: [...new Set(r.deps.filter((d) => d.ecosystem === 'pypi').map((d) => d.manifest))].slice(0, 2) });
  if (r.paths.includes('go.mod')) build.push({ label: 'go build ./...', value: 'Build the Go module', refs: ['go.mod'] });
  if (r.paths.includes('Cargo.toml')) build.push({ label: 'cargo build', value: 'Build the Rust crate', refs: ['Cargo.toml'] });
  for (const c of r.containers) build.push({ label: `${c.kind}: ${c.name}`, value: c.details.join(' · '), refs: [at(c)] });
  const needed = r.env.filter((e) => e.documented || e.refs.length);
  if (needed.length) build.push({ label: 'Settings to provide', value: list(needed.map((e) => e.name), 14), refs: needed.slice(0, 4).flatMap((e) => e.refs.slice(0, 1).map(at)) });
  s.push({ id: 'build', title: 'Build and execution process', summary: build.length ? 'The commands and settings this project uses to install, build and run.' : 'No build scripts, container files or known build tools were found.', items: build });

  // 17
  const dep: Item[] = [
    ...r.deploy.map((d) => ({ label: d.platform, value: d.detail, refs: [at(d)] })),
    ...r.workflows.map((w) => ({ label: `Workflow: ${w.name}`, value: `on ${w.triggers.join(', ') || 'unspecified'}; jobs ${w.jobs.map((j) => j.name).join(', ')}`, refs: [w.path] })),
  ];
  s.push({ id: 'deployment', title: 'Deployment architecture', summary: r.deploy.length ? `Deployed to ${list([...new Set(r.deploy.map((d) => d.platform))])}${r.workflows.length ? `, by ${plural(r.workflows.length, 'CI workflow')}` : ''}.` : r.workflows.length ? `${plural(r.workflows.length, 'CI workflow')}, but no deployment target was identified.` : 'No deployment configuration or CI workflow was found.', items: dep });

  // 18
  const high = r.secrets.filter((f) => f.severity === 'high');
  const info = r.secrets.filter((f) => f.severity === 'info');
  const sec: Item[] = [
    ...high.map((f) => ({ label: `Possible ${f.kind}`, value: 'The value has been removed from this report. If it is real, revoke it and remove it from the history.', refs: [`${f.path}:${f.line}`] })),
    ...info.map((f) => ({ label: f.kind, value: 'Public by design: it names the Firebase project and ships in the app. Check that API restrictions are set on it in Google Cloud.', refs: [`${f.path}:${f.line}`] })),
    ...r.committedEnvFiles.map((p) => ({ label: 'Environment file committed', value: 'A .env file is in the repository; it was not read. Files like this usually hold secrets and belong in .gitignore.', refs: [p] })),
    { label: 'Security policy', value: r.quality.hasSecurityPolicy ? 'SECURITY.md tells people how to report a vulnerability.' : 'No SECURITY.md: there is no stated way to report a vulnerability.' },
    { label: 'Dependency updates', value: r.quality.dependencyUpdates ? 'Automated (Dependabot or Renovate).' : 'Not automated: outdated or vulnerable versions are only caught by hand.' },
    ...auth.length ? [] : [{ label: 'Authentication', value: 'No authentication library found. That is right for a public site or a library; for an app with accounts it is worth checking.' }],
    ...(t.some((x) => x.name === 'bcrypt') ? [{ label: 'Password storage', value: 'Passwords are hashed with a dedicated algorithm.', refs: t.find((x) => x.name === 'bcrypt')!.evidence }] : []),
  ];
  s.push({ id: 'security', title: 'Security analysis', summary: high.length ? `${plural(high.length, 'possible secret')} found in the files read (values removed).` : 'No credentials were found in the files read.', items: sec });

  // 19
  const q = r.quality;
  s.push({
    id: 'quality', title: 'Code quality analysis',
    summary: `${plural(q.testFiles, 'test file')} for ${plural(q.sourceFiles, 'source file')}${q.ciRunsTests ? ', run by CI on every change' : ''}; ${q.linters.length ? `checked by ${list(q.linters)}` : 'no linter configuration found'}.`,
    items: [
      { label: 'Tests', value: q.testFiles ? `${q.testFiles} test files (${Math.round((q.testFiles / Math.max(q.sourceFiles, 1)) * 100)}% of source files)` : 'No test files found' },
      { label: 'Tests in CI', value: q.ciRunsTests ? 'Yes' : 'No CI step runs tests' },
      { label: 'Static typing', value: q.typeChecked ? 'Yes' : 'No type checking configured' },
      { label: 'Linters and formatters', value: q.linters.join(', ') || 'None found' },
      { label: 'TODO / FIXME notes', value: String(q.todoCount) },
      { label: 'Documentation', value: [q.hasReadme && 'README', q.hasContributing && 'CONTRIBUTING', q.hasLicense && 'LICENSE'].filter(Boolean).join(', ') || 'None' },
      ...q.largestFiles.slice(0, 3).map((f) => ({ label: `Large file: ${f.path}`, value: `${f.lines} lines`, refs: [f.path] })),
    ],
  });

  // 20
  const perf: Item[] = [];
  if (t.some((x) => x.name === 'Redis')) perf.push({ label: 'Caching', value: 'Redis is available for caching or queues.' });
  if (byCat(t, 'Messaging').length) perf.push({ label: 'Background work', value: `Slow work runs off the request path (${list(byCat(t, 'Messaging').map((x) => x.name))}).` });
  if (byCat(t, 'Backend-as-a-service').length) perf.push({ label: 'Managed backend', value: `${list(byCat(t, 'Backend-as-a-service').map((x) => x.name))} scales the database and auth without servers to run.` });
  if (t.some((x) => /Kubernetes|Docker Compose/.test(x.name))) perf.push({ label: 'Containers', value: 'Services run in containers, so they can be scaled out one by one.' });
  if (t.some((x) => /Vercel|Netlify|Cloudflare/.test(x.name)) || r.deploy.some((d) => /Cloudflare|Vercel|Netlify/.test(d.platform))) perf.push({ label: 'Edge hosting', value: 'Static assets and functions are served from a global edge network.' });
  if (q.largestFiles[0]?.lines > 1500) perf.push({ label: 'Large files', value: `${q.largestFiles[0].path} has ${q.largestFiles[0].lines} lines; files this size are harder to change safely.`, refs: [q.largestFiles[0].path] });
  s.push({ id: 'performance', title: 'Scalability and performance observations', summary: perf.length ? 'What in the stack helps or limits growth.' : 'Nothing specific to scaling was found.', items: perf });

  // 21
  const strengths: Item[] = [];
  if (q.ciRunsTests) strengths.push({ label: 'Automated testing', value: 'CI runs the tests on every change.', refs: r.workflows.slice(0, 2).map((w) => w.path) });
  if (q.typeChecked) strengths.push({ label: 'Typed code', value: 'Type checking catches mistakes before running.' });
  if (q.linters.length) strengths.push({ label: 'Consistent style', value: list(q.linters) });
  if (q.dependencyUpdates) strengths.push({ label: 'Dependencies kept current', value: 'Updates are proposed automatically.' });
  if (r.deploy.length && r.workflows.length) strengths.push({ label: 'Automated deployment', value: `Deploys to ${list([...new Set(r.deploy.map((d) => d.platform))], 3)} from CI.` });
  if (r.modules.length >= 4) strengths.push({ label: 'Organised into modules', value: `${plural(r.modules.length, 'module')} with distinct roles.` });
  if (q.hasReadme && q.hasLicense) strengths.push({ label: 'Documented and licensed', value: `README and ${r.repo.license ?? 'a license'}.` });
  if (!high.length) strengths.push({ label: 'No secrets in the code read', value: 'Credentials appear to be kept out of the repository.' });
  s.push({ id: 'strengths', title: 'Technical strengths', summary: strengths.length ? `${plural(strengths.length, 'strength')} the evidence supports.` : 'No particular strengths stood out from what was read.', items: strengths });

  // 22
  const improve: Item[] = [];
  for (const f of high.slice(0, 3)) improve.push({ label: 'Remove a possible secret', value: `${f.kind} at ${f.path}:${f.line}; revoke it and rewrite history.`, refs: [`${f.path}:${f.line}`] });
  if (!q.testFiles) improve.push({ label: 'Add tests', value: 'No tests were found; even a few around the core logic catch regressions.' });
  else if (!q.ciRunsTests) improve.push({ label: 'Run the tests in CI', value: 'Tests exist but no workflow runs them on each change.' });
  if (!r.workflows.length) improve.push({ label: 'Add continuous integration', value: 'No CI workflow: nothing checks a change before it lands.' });
  if (!q.dependencyUpdates) improve.push({ label: 'Automate dependency updates', value: 'Add Dependabot or Renovate to hear of outdated and vulnerable versions.' });
  if (!q.lockfiles.length && r.deps.length) improve.push({ label: 'Commit a lock file', value: 'Without one, two installs of the same commit can get different versions.' });
  if (!q.linters.length && q.sourceFiles > 10) improve.push({ label: 'Add a linter', value: 'A linter keeps style consistent and catches common mistakes.' });
  if (!q.hasSecurityPolicy) improve.push({ label: 'Add SECURITY.md', value: 'Say how to report a vulnerability privately.' });
  if (r.env.length && !r.env.some((e) => e.documented)) improve.push({ label: 'Document the settings', value: `The code reads ${plural(r.env.length, 'environment variable')} but there is no .env.example listing them.`, refs: r.env.slice(0, 2).flatMap((e) => e.refs.slice(0, 1).map(at)) });
  if (q.largestFiles[0]?.lines > 1500) improve.push({ label: 'Split the largest file', value: `${q.largestFiles[0].path} (${q.largestFiles[0].lines} lines).`, refs: [q.largestFiles[0].path] });
  if (!q.hasReadme) improve.push({ label: 'Write a README', value: 'Explain what the project is and how to run it.' });
  s.push({ id: 'improvements', title: 'Potential improvements', summary: improve.length ? `${plural(improve.length, 'suggestion')}, most important first.` : 'Nothing obvious to improve from what was read.', items: improve });

  // 23
  s.push({
    id: 'summary', title: 'Complete technical summary',
    summary: [
      `${r.repo.fullName} is ${langs.length ? `a ${langs.slice(0, 2).map(([l]) => l).join(' and ')} project` : 'a project'}${front.length ? ` with a ${list(front.map((x) => x.name), 2)} front end` : ''}${back.length ? `${front.length ? ' and' : ' with'} a ${list(back.map((x) => x.name), 2)} back end` : ''}.`,
      byCat(t, 'Database').length ? `Its data lives in ${list(byCat(t, 'Database').map((x) => x.name), 3)}${r.entities.length ? ` (${plural(r.entities.length, 'table')})` : ''}.` : '',
      r.endpoints.length ? `It exposes ${plural(r.endpoints.length, 'route')}.` : '',
      auth.length ? `People sign in with ${list(auth.map((x) => x.name), 2)}.` : '',
      r.deploy.length ? `It is deployed to ${list([...new Set(r.deploy.map((d) => d.platform))], 3)}${r.workflows.length ? ' by CI' : ''}.` : '',
      `${plural(q.testFiles, 'test file')}; ${high.length ? plural(high.length, 'possible secret') + ' to look at' : 'no secrets found'}.`,
    ].filter(Boolean).join(' '),
    items: [],
  });

  return s;
}
