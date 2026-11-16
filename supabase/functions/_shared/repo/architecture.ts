// How the parts of a repository fit together: its modules, and diagrams of
// the system, its modules, its data, its API and its sign-in.
//
// A diagram here is a graph (nodes, edges) the app draws itself, plus the
// same graph as Mermaid for anyone exporting the report. Nodes only exist
// for what the analysis found — a technology, a module, a table, a route —
// and each carries the paths that show it, so a diagram can be clicked
// through to its evidence. Nothing is added to make a picture look complete.

import type { Dependency, Tech } from './detect.ts';
import type { Endpoint, Entity, Ref, Relation, Workflow, DeployTarget } from './extract.ts';

export interface GraphNode {
  id: string;
  label: string;
  /** client | service | data | external | module | entity | infra | person | route */
  kind: string;
  detail?: string;
  refs?: string[];
}

export interface GraphEdge {
  from: string;
  to: string;
  label?: string;
}

export interface Graph {
  id: string;
  title: string;
  /** 'flow' draws left to right in layers; 'network' places nodes by links. */
  layout: 'flow' | 'network';
  nodes: GraphNode[];
  edges: GraphEdge[];
  note: string;
  mermaid: string;
}

export interface Module {
  id: string;
  path: string;
  role: string;
  files: number;
  languages: string[];
  keyFiles: string[];
  imports: string[];
  importedBy: string[];
}

const ROOTS = new Set(['src', 'lib', 'app', 'pkg', 'internal', 'cmd', 'source', 'server', 'client', 'backend', 'frontend', 'api', 'web']);
const GROUPS = new Set(['packages', 'apps', 'services', 'modules', 'libs', 'crates', 'features']);

/// The module a file belongs to: a second-level folder under a source root
/// (src/components), a package of a monorepo (packages/ui), or else the
/// top-level folder.
export function moduleOf(path: string): string {
  const parts = path.split('/');
  if (parts.length === 1) return '(root)';
  const dirs = parts.slice(0, -1);
  if (dirs[0] === 'supabase' && dirs[1]) {
    if (dirs[1] === 'functions' && dirs[2] === '_shared') return 'supabase/functions/_shared';
    return `supabase/${dirs[1]}`;
  }
  if (dirs[0] === '.github') return '.github';
  if (GROUPS.has(dirs[0]) && dirs[1]) return `${dirs[0]}/${dirs[1]}`;
  if (ROOTS.has(dirs[0])) {
    if (dirs[1] && (GROUPS.has(dirs[1]) || ROOTS.has(dirs[1])) && dirs[2]) return `${dirs[0]}/${dirs[1]}/${dirs[2]}`;
    return dirs[1] ? `${dirs[0]}/${dirs[1]}` : dirs[0];
  }
  return dirs[0];
}

const ROLES: [RegExp, string][] = [
  [/(^|\/)(components?|widgets?|ui)$/i, 'Reusable UI components'],
  [/(^|\/)(pages|screens|views|routes|app)$/i, 'Pages and screens'],
  [/(^|\/)features?\/[^/]+$/i, 'A feature: its screens and logic together'],
  [/(^|\/)(api|controllers?|handlers?|endpoints?|resolvers|routers?)$/i, 'API layer: receives requests and answers them'],
  [/(^|\/)supabase\/functions$/i, 'Serverless functions (Supabase Edge Functions)'],
  [/(^|\/)_shared$/i, 'Code shared between server functions'],
  [/(^|\/)(services?|usecases?|domain|core|business)$/i, 'Business logic and services'],
  [/(^|\/)(models?|entities|schemas?|types|dto)$/i, 'Data models and types'],
  [/(^|\/)(db|database|migrations?|prisma|sql|repositor(y|ies)|dao|persistence)$/i, 'Database access and schema'],
  [/(^|\/)(store|stores|state|redux|providers?|bloc|context)$/i, 'Application state'],
  [/(^|\/)hooks$/i, 'Reusable React hooks'],
  [/(^|\/)(auth|authentication|security|identity)$/i, 'Sign-in and access control'],
  [/(^|\/)(utils?|helpers?|common|shared|lib|libs)$/i, 'Shared utilities'],
  [/(^|\/)(config|configs|settings|env)$/i, 'Configuration'],
  [/(^|\/)(tests?|__tests__|spec|e2e|integration_test)$/i, 'Tests'],
  [/(^|\/)(scripts?|tools?|bin)$/i, 'Developer tooling and scripts'],
  [/(^|\/)(docs?|documentation)$/i, 'Documentation'],
  [/(^|\/)(public|static|assets|res|resources)$/i, 'Static assets'],
  [/(^|\/)\.github$/i, 'CI/CD workflows and repository settings'],
  [/(^|\/)(android|ios|macos|windows|linux|web)$/i, 'Platform runner (native project for one platform)'],
  [/(^|\/)(infra|infrastructure|deploy|deployment|k8s|helm|terraform|ops|docker)$/i, 'Infrastructure and deployment'],
  [/(^|\/)(scrapers?|crawlers?|jobs|workers?|tasks|cron)$/i, 'Background jobs'],
  [/(^|\/)(i18n|l10n|locales?|translations?)$/i, 'Translations'],
  [/(^|\/)(styles?|css|theme|themes)$/i, 'Styles and theme'],
  [/(^|\/)(middlewares?)$/i, 'Request middleware'],
  [/(^|\/)(notifications?)$/i, 'Notifications'],
];

export function roleOf(module: string): string {
  if (module === '(root)') return 'Top-level configuration and documentation';
  for (const [re, role] of ROLES) if (re.test(module)) return role;
  return 'Project code';
}

export function buildModules(paths: string[], languageOf: (p: string) => string | null, imports: [string, string][]): Module[] {
  const byModule = new Map<string, string[]>();
  for (const p of paths) {
    const m = moduleOf(p);
    byModule.set(m, [...(byModule.get(m) ?? []), p]);
  }
  const indegree = new Map<string, number>();
  for (const [, to] of imports) indegree.set(to, (indegree.get(to) ?? 0) + 1);
  const modEdges = new Map<string, Set<string>>();
  const modIn = new Map<string, Set<string>>();
  for (const [from, to] of imports) {
    const a = moduleOf(from), b = moduleOf(to);
    if (a === b) continue;
    (modEdges.get(a) ?? modEdges.set(a, new Set()).get(a)!).add(b);
    (modIn.get(b) ?? modIn.set(b, new Set()).get(b)!).add(a);
  }
  const out: Module[] = [];
  for (const [path, files] of byModule) {
    const langs = new Map<string, number>();
    for (const f of files) {
      const l = languageOf(f);
      if (l) langs.set(l, (langs.get(l) ?? 0) + 1);
    }
    out.push({
      id: path,
      path,
      role: roleOf(path),
      files: files.length,
      languages: [...langs.entries()].sort((a, b) => b[1] - a[1]).map(([l]) => l).slice(0, 4),
      keyFiles: [...files].sort((a, b) => (indegree.get(b) ?? 0) - (indegree.get(a) ?? 0) || a.split('/').length - b.split('/').length).slice(0, 6),
      imports: [...(modEdges.get(path) ?? [])].sort(),
      importedBy: [...(modIn.get(path) ?? [])].sort(),
    });
  }
  return out.sort((a, b) => b.files - a.files).slice(0, 60);
}

// ---------------------------------------------------------------------------
// Diagrams
// ---------------------------------------------------------------------------

const slug = (s: string) => s.replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '') || 'n';

function mermaidOf(g: Omit<Graph, 'mermaid'>): string {
  const lines = [g.layout === 'flow' ? 'flowchart LR' : 'flowchart TB'];
  const shape = (n: GraphNode) => {
    const label = n.label.replace(/["[\]{}()<>]/g, ' ');
    if (n.kind === 'data' || n.kind === 'entity') return `${slug(n.id)}[("${label}")]`;
    if (n.kind === 'person') return `${slug(n.id)}(("${label}"))`;
    if (n.kind === 'external') return `${slug(n.id)}{{"${label}"}}`;
    return `${slug(n.id)}["${label}"]`;
  };
  for (const n of g.nodes) lines.push(`  ${shape(n)}`);
  for (const e of g.edges) {
    const label = e.label ? `|"${e.label.replace(/["|]/g, ' ')}"|` : '';
    lines.push(`  ${slug(e.from)} -->${label} ${slug(e.to)}`);
  }
  return lines.join('\n');
}

function graph(g: Omit<Graph, 'mermaid'>): Graph {
  return { ...g, mermaid: mermaidOf(g) };
}

export interface Facts {
  techs: Tech[];
  deps: Dependency[];
  endpoints: Endpoint[];
  entities: Entity[];
  relations: Relation[];
  workflows: Workflow[];
  deploy: DeployTarget[];
  entryPoints: Ref[];
  modules: Module[];
  files: Map<string, string>;
}

const cat = (f: Facts, ...c: string[]) => f.techs.filter((t) => c.includes(t.category));
const names = (ts: Tech[]) => ts.map((t) => t.name).join(', ');

/// Calls from one place to another, seen in its source: an HTTP client, a
/// fetch, a BaaS client or a function invocation.
function callsOut(files: Map<string, string>, where: (p: string) => boolean): string[] {
  const out: string[] = [];
  for (const [p, t] of files) {
    if (!where(p)) continue;
    const m = /\b(fetch\(|axios\.|http\.(get|post)\(|Dio\(|functions\.invoke\(|\.from\(['"]\w+['"]\)|supabase\.|firebase\.|createClient\(|requests\.(get|post)\(|HttpClient)/.exec(t);
    if (m) out.push(`${p}:${t.slice(0, m.index).split('\n').length}`);
    if (out.length >= 4) break;
  }
  return out;
}

export function buildGraphs(f: Facts): Graph[] {
  const graphs: Graph[] = [];

  // --- System -------------------------------------------------------------
  {
    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];
    const front = cat(f, 'Frontend', 'Mobile', 'Desktop');
    const back = cat(f, 'Backend').filter((t) => t.name !== 'Node.js' || f.endpoints.some((e) => e.framework === 'Node.js router'));
    const baas = cat(f, 'Backend-as-a-service');
    const dbs = cat(f, 'Database');
    const ext = cat(f, 'AI/ML', 'Payments', 'Monitoring', 'Integration', 'Messaging', 'Realtime').filter((t) => t.confidence === 'confirmed' && !/NumPy|scikit|PyTorch|TensorFlow|Transformers/.test(t.name));
    const hosts = [...new Set(f.deploy.map((d) => d.platform))];
    nodes.push({ id: 'user', label: 'User', kind: 'person' });
    if (front.length) {
      nodes.push({ id: 'frontend', label: `Frontend\n${names(front)}`, kind: 'client', refs: front.flatMap((t) => t.evidence).slice(0, 6) });
      edges.push({ from: 'user', to: 'frontend', label: 'uses' });
    }
    if (back.length || f.endpoints.length) {
      const fw = [...new Set(f.endpoints.map((e) => e.framework.split(' →')[0]))];
      nodes.push({ id: 'backend', label: `Backend / API\n${names(back) || fw.join(', ')}`, kind: 'service', detail: `${f.endpoints.length} endpoint${f.endpoints.length === 1 ? '' : 's'} found`, refs: [...back.flatMap((t) => t.evidence), ...f.endpoints.slice(0, 3).map((e) => `${e.path}:${e.line}`)].slice(0, 6) });
      const src = front.length ? 'frontend' : 'user';
      const evidence = front.length ? callsOut(f.files, (p) => !/(^|\/)(server|backend|api|supabase\/functions)\//.test(p)) : [];
      edges.push({ from: src, to: 'backend', label: evidence.length ? 'HTTP requests' : 'requests' });
    }
    for (const b of baas) {
      const id = `baas_${slug(b.name)}`;
      nodes.push({ id, label: b.name, kind: 'service', detail: b.purpose, refs: b.evidence });
      if (front.length) edges.push({ from: 'frontend', to: id, label: 'client SDK' });
      if (nodes.some((n) => n.id === 'backend')) edges.push({ from: 'backend', to: id });
    }
    for (const d of dbs) {
      const id = `db_${slug(d.name)}`;
      nodes.push({ id, label: d.name, kind: 'data', detail: d.purpose, refs: d.evidence });
      const owner = baas.find((b) => b.name === 'Supabase') && /PostgreSQL|pgvector/.test(d.name) ? 'baas_Supabase'
        : baas.find((b) => b.name === 'Firebase') && /Firestore/.test(d.name) ? 'baas_Firebase'
        : nodes.some((n) => n.id === 'backend') ? 'backend' : front.length ? 'frontend' : null;
      if (owner) edges.push({ from: owner, to: id, label: 'reads / writes' });
    }
    for (const e of ext.slice(0, 6)) {
      const id = `ext_${slug(e.name)}`;
      nodes.push({ id, label: e.name, kind: 'external', detail: e.purpose, refs: e.evidence });
      const from = nodes.some((n) => n.id === 'backend') ? 'backend' : baas.length ? `baas_${slug(baas[0].name)}` : front.length ? 'frontend' : 'user';
      edges.push({ from, to: id, label: 'calls' });
    }
    if (f.workflows.length) {
      nodes.push({ id: 'ci', label: 'CI/CD\nGitHub Actions', kind: 'infra', refs: f.workflows.map((w) => w.path).slice(0, 6) });
      for (const h of hosts.slice(0, 5)) {
        const id = `host_${slug(h)}`;
        nodes.push({ id, label: h, kind: 'infra', refs: f.deploy.filter((d) => d.platform === h).map((d) => `${d.path}:${d.line}`) });
        edges.push({ from: 'ci', to: id, label: 'deploys' });
      }
    } else {
      for (const h of hosts.slice(0, 4)) nodes.push({ id: `host_${slug(h)}`, label: h, kind: 'infra', refs: f.deploy.filter((d) => d.platform === h).map((d) => d.path) });
    }
    if (nodes.length > 1) {
      graphs.push(graph({ id: 'system', title: 'System architecture', layout: 'flow', nodes, edges, note: 'Each box is a technology or part found in the repository; links are drawn where the code shows one part using another.' }));
    }
  }

  // --- Modules ------------------------------------------------------------
  {
    const linked = f.modules.filter((m) => m.imports.length || m.importedBy.length);
    const pick = (linked.length >= 3 ? linked : f.modules).slice(0, 24);
    const ids = new Set(pick.map((m) => m.id));
    const nodes = pick.map((m) => ({ id: m.id, label: m.path, kind: 'module', detail: `${m.role} · ${m.files} files`, refs: m.keyFiles.slice(0, 4) }));
    const edges = pick.flatMap((m) => m.imports.filter((t) => ids.has(t)).map((t) => ({ from: m.id, to: t, label: 'imports' })));
    if (nodes.length >= 2) {
      graphs.push(graph({ id: 'modules', title: 'Modules and their dependencies', layout: 'network', nodes, edges, note: edges.length ? 'An arrow means files in one module import files in the other.' : 'No imports between modules could be resolved; modules are shown on their own.' }));
    }
  }

  // --- Database -----------------------------------------------------------
  if (f.entities.length) {
    const nodes = f.entities.slice(0, 40).map((e) => ({ id: e.name, label: e.name, kind: 'entity', detail: e.columns.slice(0, 8).map((c) => `${c.name}: ${c.type}`).join('\n') || e.source, refs: [`${e.path}:${e.line}`] }));
    const ids = new Set(nodes.map((n) => n.id.toLowerCase()));
    const canon = new Map(nodes.map((n) => [n.id.toLowerCase(), n.id]));
    const edges = f.relations.filter((r) => ids.has(r.from.toLowerCase()) && ids.has(r.to.toLowerCase())).map((r) => ({ from: canon.get(r.from.toLowerCase())!, to: canon.get(r.to.toLowerCase())!, label: r.label }));
    graphs.push(graph({ id: 'database', title: 'Database tables and relationships', layout: 'network', nodes, edges, note: `${f.entities.length} table${f.entities.length === 1 ? '' : 's'} or model${f.entities.length === 1 ? '' : 's'} read from ${[...new Set(f.entities.map((e) => e.source))].join(', ')}. Arrows are foreign keys or relation fields.` }));
  }

  // --- API ----------------------------------------------------------------
  if (f.endpoints.length) {
    const nodes: GraphNode[] = [{ id: 'client', label: 'Client', kind: 'client' }];
    const edges: GraphEdge[] = [];
    const byGroup = new Map<string, Endpoint[]>();
    for (const e of f.endpoints) {
      const key = e.route.split('/').filter(Boolean).slice(0, e.route.startsWith('/functions/v1') ? 3 : 1).join('/') || '/';
      byGroup.set(key, [...(byGroup.get(key) ?? []), e]);
    }
    for (const [key, list] of [...byGroup.entries()].slice(0, 18)) {
      const id = `route_${slug(key)}`;
      nodes.push({ id, label: `/${key.replace(/^\//, '')}`, kind: 'route', detail: list.slice(0, 6).map((e) => `${e.method} ${e.route}`).join('\n'), refs: list.slice(0, 4).map((e) => `${e.path}:${e.line}`) });
      edges.push({ from: 'client', to: id, label: [...new Set(list.map((e) => e.method))].slice(0, 3).join('/') });
    }
    const store = cat(f, 'Database', 'Backend-as-a-service')[0];
    if (store) {
      nodes.push({ id: 'store', label: store.name, kind: 'data', refs: store.evidence });
      for (const n of nodes.filter((n) => n.kind === 'route')) edges.push({ from: n.id, to: 'store' });
    }
    graphs.push(graph({ id: 'api', title: 'API endpoints', layout: 'flow', nodes, edges, note: `${f.endpoints.length} route declaration${f.endpoints.length === 1 ? '' : 's'}, grouped by their first path segment.${store ? ` Links to ${store.name} show the data store the backend uses, not that every route touches it.` : ''}` }));
  }

  // --- Sign-in ------------------------------------------------------------
  const auth = cat(f, 'Auth');
  if (auth.length) {
    const nodes: GraphNode[] = [{ id: 'user', label: 'User', kind: 'person' }];
    const edges: GraphEdge[] = [];
    const front = cat(f, 'Frontend', 'Mobile', 'Desktop');
    const provider = auth.find((a) => /Firebase|Supabase|Clerk|Auth0|NextAuth|Django auth|Devise|Spring Security|Passport/.test(a.name)) ?? auth[0];
    const tokens = auth.find((a) => a.name === 'JSON Web Tokens');
    const hashing = auth.find((a) => a.name === 'bcrypt');
    if (front.length) {
      nodes.push({ id: 'app', label: names(front.slice(0, 2)), kind: 'client' });
      edges.push({ from: 'user', to: 'app', label: 'signs in' });
    }
    nodes.push({ id: 'provider', label: provider.name, kind: /Firebase|Supabase|Clerk|Auth0/.test(provider.name) ? 'external' : 'service', detail: provider.purpose, refs: provider.evidence });
    edges.push({ from: front.length ? 'app' : 'user', to: 'provider', label: 'credentials' });
    if (hashing) {
      nodes.push({ id: 'hash', label: 'Password hashing', kind: 'service', detail: hashing.name, refs: hashing.evidence });
      edges.push({ from: 'provider', to: 'hash' });
    }
    const verifies = [...f.files].find(([, t]) => /verify(Id)?Token|jwt\.verify|jwtVerify|decode\(.*verify|getUser\(|auth\.uid\(\)|current_uid\(\)|@login_required|IsAuthenticated|requireAuth|authenticate\(/.test(t));
    if (tokens || verifies) {
      nodes.push({ id: 'token', label: tokens ? 'Signed token (JWT)' : 'Session token', kind: 'service', refs: tokens?.evidence ?? [] });
      edges.push({ from: 'provider', to: 'token', label: 'issues' });
      if (nodes.some((n) => n.id === 'app')) edges.push({ from: 'token', to: 'app', label: 'held by' });
    }
    if (verifies) {
      const [p, t] = verifies;
      const line = t.slice(0, t.search(/verify(Id)?Token|jwt\.verify|jwtVerify|getUser\(|auth\.uid\(\)|current_uid\(\)|@login_required|IsAuthenticated|requireAuth|authenticate\(/)).split('\n').length;
      nodes.push({ id: 'check', label: 'Server checks the token', kind: 'service', refs: [`${p}:${line}`] });
      edges.push({ from: nodes.some((n) => n.id === 'token') ? 'token' : 'provider', to: 'check', label: 'sent with requests' });
      const db = cat(f, 'Database')[0];
      if (db) {
        nodes.push({ id: 'data', label: `${db.name}\n(user's own data)`, kind: 'data', refs: db.evidence });
        edges.push({ from: 'check', to: 'data', label: 'allowed' });
      }
    }
    graphs.push(graph({ id: 'auth', title: 'Sign-in and access', layout: 'flow', nodes, edges, note: `Built from the authentication libraries found (${names(auth)})${verifies ? ' and the code that checks a token' : ''}.` }));
  }

  return graphs;
}
