// Facts read out of source: endpoints, tables, settings, pipelines, containers,
// deployment targets, entry points and who imports whom.
//
// Each extractor is a set of patterns for the frameworks people actually use,
// and each fact keeps the file and line it came from. Nothing is inferred
// from a name alone: an endpoint is a route declaration, a table is a CREATE
// TABLE or a model class, a setting is a variable the code reads.

import type { Files } from './detect.ts';
import { envNames } from './secrets.ts';
import { isEnvExample } from './select.ts';

export interface Ref {
  path: string;
  line: number;
}

const lineAt = (text: string, index: number) => text.slice(0, index).split('\n').length;

// ---------------------------------------------------------------------------
// API endpoints
// ---------------------------------------------------------------------------

export interface Endpoint extends Ref {
  method: string;
  route: string;
  framework: string;
}

export function extractEndpoints(files: Files): Endpoint[] {
  const out: Endpoint[] = [];
  const push = (e: Endpoint) => {
    if (out.length < 400 && !out.some((o) => o.method === e.method && o.route === e.route && o.path === e.path)) out.push(e);
  };
  for (const [path, text] of files) {
    if (/\.(c|m)?[jt]sx?$/.test(path)) {
      // Express, Koa router, Fastify, Hono: app.get('/x', ...)
      for (const m of text.matchAll(/\b(?:app|router|server|api|route|routes|fastify|hono)\.(get|post|put|patch|delete|options|all)\s*\(\s*(['"`])(\/[^'"`]*)\2/gi)) {
        push({ path, line: lineAt(text, m.index!), method: m[1].toUpperCase(), route: m[3], framework: 'Node.js router' });
      }
      // NestJS: @Controller('users') + @Get(':id')
      const ctrl = /@Controller\(\s*['"`]?([^'"`)]*)['"`]?\s*\)/.exec(text);
      if (ctrl) {
        for (const m of text.matchAll(/@(Get|Post|Put|Patch|Delete)\(\s*['"`]?([^'"`)]*)['"`]?\s*\)/g)) {
          push({ path, line: lineAt(text, m.index!), method: m[1].toUpperCase(), route: `/${[ctrl[1], m[2]].filter(Boolean).join('/')}`.replace(/\/+/g, '/'), framework: 'NestJS' });
        }
      }
      // Next.js App Router: app/**/route.ts exporting GET/POST...
      const app = /(?:^|\/)app\/(.*?)\/?route\.(?:c|m)?[jt]sx?$/.exec(path);
      if (app) {
        for (const m of text.matchAll(/export\s+(?:async\s+)?(?:function|const)\s+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/g)) {
          push({ path, line: lineAt(text, m.index!), method: m[1], route: `/${app[1]}`.replace(/\([^)]*\)\//g, '').replace(/\/$/, '') || '/', framework: 'Next.js route handler' });
        }
      }
      // Next.js Pages API: pages/api/**
      const pages = /(?:^|\/)pages\/(api\/.*?)(?:\/index)?\.(?:c|m)?[jt]sx?$/.exec(path);
      if (pages) push({ path, line: 1, method: 'ANY', route: `/${pages[1]}`, framework: 'Next.js API route' });
      // Supabase Edge Functions / Deno.serve handlers
      const fn = /(?:^|\/)supabase\/functions\/([^/_][^/]*)\/index\.ts$/.exec(path);
      if (fn) {
        const methods = [...new Set([...text.matchAll(/req\.method\s*[!=]==?\s*['"](GET|POST|PUT|PATCH|DELETE)['"]/g)].map((m) => m[1]))];
        push({ path, line: 1, method: methods.filter((x) => x !== 'OPTIONS').join('/') || 'POST', route: `/functions/v1/${fn[1]}`, framework: 'Supabase Edge Function' });
      }
      // Cloudflare / Vercel / Netlify functions directories
      const sl = /(?:^|\/)(?:api|netlify\/functions|functions)\/([^.]+)\.(?:c|m)?[jt]s$/.exec(path);
      if (sl && !fn && !pages && !app && /export\s+(default|async function handler|const handler|function onRequest)/.test(text)) {
        push({ path, line: 1, method: 'ANY', route: `/${sl[0].replace(/\.(c|m)?[jt]s$/, '').replace(/^.*?(api|functions)\//, '$1/')}`, framework: 'Serverless function' });
      }
    } else if (/\.py$/.test(path)) {
      // FastAPI / Flask: @app.get("/x"), @router.post(...), @app.route("/x", methods=["POST"])
      const prefix = /APIRouter\([^)]*prefix\s*=\s*['"]([^'"]+)['"]/.exec(text)?.[1] ?? '';
      for (const m of text.matchAll(/@\w+\.(get|post|put|patch|delete|api_route)\(\s*['"]([^'"]*)['"]/g)) {
        push({ path, line: lineAt(text, m.index!), method: m[1] === 'api_route' ? 'ANY' : m[1].toUpperCase(), route: `${prefix}${m[2]}` || '/', framework: 'FastAPI' });
      }
      for (const m of text.matchAll(/@\w+\.route\(\s*['"]([^'"]*)['"](?:[^)]*methods\s*=\s*\[([^\]]*)\])?/g)) {
        const methods = (m[2] ?? "'GET'").match(/[A-Z]+/g) ?? ['GET'];
        push({ path, line: lineAt(text, m.index!), method: methods.join('/'), route: m[1] || '/', framework: 'Flask' });
      }
      // Django: path('users/<int:id>/', view)
      if (/urls\.py$/.test(path)) {
        for (const m of text.matchAll(/\b(?:re_)?path\(\s*r?['"]([^'"]*)['"]\s*,\s*([\w.]+)/g)) {
          push({ path, line: lineAt(text, m.index!), method: 'ANY', route: `/${m[1]}`, framework: `Django → ${m[2]}` });
        }
      }
    } else if (/\.(java|kt)$/.test(path)) {
      const base = /@RequestMapping\(\s*(?:value\s*=\s*|path\s*=\s*)?["']([^"']*)["']/.exec(text)?.[1] ?? '';
      for (const m of text.matchAll(/@(Get|Post|Put|Patch|Delete|Request)Mapping\(\s*(?:value\s*=\s*|path\s*=\s*)?["']?([^"')]*)["']?/g)) {
        if (m[1] === 'Request' && m.index === text.indexOf('@RequestMapping')) continue;
        push({ path, line: lineAt(text, m.index!), method: m[1] === 'Request' ? 'ANY' : m[1].toUpperCase(), route: `${base}${m[2]}` || '/', framework: 'Spring' });
      }
    } else if (/\.go$/.test(path)) {
      for (const m of text.matchAll(/\.(GET|POST|PUT|PATCH|DELETE|Get|Post|Put|Patch|Delete|HandleFunc|Handle)\(\s*"(\/[^"]*)"/g)) {
        push({ path, line: lineAt(text, m.index!), method: /^Handle/.test(m[1]) ? 'ANY' : m[1].toUpperCase(), route: m[2], framework: 'Go HTTP' });
      }
    } else if (/routes\.rb$/.test(path)) {
      for (const m of text.matchAll(/^\s*(get|post|put|patch|delete|resources?)\s+['":]([^'",\s]+)/gm)) {
        push({ path, line: lineAt(text, m.index!), method: /resources?/.test(m[1]) ? 'REST' : m[1].toUpperCase(), route: `/${m[2]}`, framework: 'Rails' });
      }
    } else if (/\.(ya?ml|json)$/.test(path) && /openapi|swagger/i.test(path)) {
      for (const m of text.matchAll(/^ {2}["']?(\/[^"':\s]*)["']?:\s*$/gm)) {
        push({ path, line: lineAt(text, m.index!), method: 'SPEC', route: m[1], framework: 'OpenAPI' });
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Database schema
// ---------------------------------------------------------------------------

export interface Entity extends Ref {
  name: string;
  columns: { name: string; type: string }[];
  source: string;
}

export interface Relation {
  from: string;
  to: string;
  label: string;
}

export function extractSchema(files: Files): { entities: Entity[]; relations: Relation[] } {
  const entities: Entity[] = [];
  const relations: Relation[] = [];
  const seen = new Set<string>();
  const addEntity = (e: Entity) => {
    const key = e.name.toLowerCase();
    if (seen.has(key) || entities.length >= 80) return;
    seen.add(key);
    entities.push(e);
  };
  const addRel = (from: string, to: string, label: string) => {
    if (from && to && from !== to && !relations.some((r) => r.from === from && r.to === to && r.label === label)) relations.push({ from, to, label });
  };
  for (const [path, text] of files) {
    if (/\.sql$/i.test(path)) {
      for (const m of text.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:"?[\w]+"?\.)?"?(\w+)"?\s*\(([\s\S]*?)\)\s*;/gi)) {
        const name = m[1];
        const cols: { name: string; type: string }[] = [];
        for (const line of m[2].split(/,\s*\n/)) {
          const c = /^\s*"?(\w+)"?\s+([a-z][\w ()[\],]*?)(?:\s+(?:not|null|primary|references|default|unique|check|generated|constraint)\b|$)/i.exec(line.trim());
          if (c && !/^(constraint|primary|foreign|unique|check|exclude)$/i.test(c[1])) cols.push({ name: c[1], type: c[2].trim().split(/\s/)[0] });
          const fk = /references\s+(?:"?\w+"?\.)?"?(\w+)"?/i.exec(line);
          if (fk) addRel(name, fk[1], c?.[1] ?? 'references');
        }
        addEntity({ path, line: lineAt(text, m.index!), name, columns: cols.slice(0, 40), source: 'SQL' });
      }
      for (const m of text.matchAll(/alter\s+table\s+(?:only\s+)?(?:"?\w+"?\.)?"?(\w+)"?[^;]*?foreign\s+key\s*\(\s*"?(\w+)"?\s*\)\s*references\s+(?:"?\w+"?\.)?"?(\w+)"?/gi)) {
        addRel(m[1], m[3], m[2]);
      }
    } else if (/\.prisma$/.test(path)) {
      for (const m of text.matchAll(/^model\s+(\w+)\s*\{([\s\S]*?)^\}/gm)) {
        const cols: { name: string; type: string }[] = [];
        for (const line of m[2].split('\n')) {
          const c = /^\s*(\w+)\s+(\w+)(\[\])?\??/.exec(line);
          if (!c || line.trim().startsWith('@@')) continue;
          cols.push({ name: c[1], type: c[2] + (c[3] ?? '') });
          if (/@relation/.test(line) || /^[A-Z]/.test(c[2])) {
            if (/^[A-Z]/.test(c[2]) && !['String', 'Int', 'Boolean', 'DateTime', 'Float', 'Decimal', 'Json', 'BigInt', 'Bytes'].includes(c[2])) {
              addRel(m[1], c[2], c[3] ? 'has many' : c[1]);
            }
          }
        }
        addEntity({ path, line: lineAt(text, m.index!), name: m[1], columns: cols.slice(0, 40), source: 'Prisma' });
      }
    } else if (/\.py$/.test(path)) {
      for (const m of text.matchAll(/^class\s+(\w+)\s*\(([^)]*(?:models\.Model|Base|db\.Model|SQLModel|Document|table\s*=\s*True)[^)]*)\)\s*:([\s\S]*?)(?=^\S|$(?![\s\S]))/gm)) {
        // SQLModel classes are tables only with table=True; the rest are the
        // shapes of requests and responses.
        if (/SQLModel/.test(m[2]) && !/table\s*=\s*True/.test(m[2])) continue;
        const cols: { name: string; type: string }[] = [];
        for (const c of m[3].matchAll(/^\s+(\w+)\s*(?::\s*[\w[\], |.]+)?\s*=\s*(?:models|db|sa)?\.?(\w+(?:Field|Column|Key)?)\(([^)]*)/gm)) {
          cols.push({ name: c[1], type: c[2] });
          const fk = /(?:ForeignKey|OneToOneField|ManyToManyField)\(\s*['"]?([\w.]+)['"]?/.exec(c[0]) ?? /foreign_key\s*=\s*['"](\w+)\./.exec(c[0]);
          if (fk) addRel(m[1], fk[1].split('.').pop()!, c[1]);
        }
        if (cols.length) addEntity({ path, line: lineAt(text, m.index!), name: m[1], columns: cols.slice(0, 40), source: /models\.Model/.test(m[2]) ? 'Django model' : 'SQLAlchemy model' });
      }
    } else if (/\.(c|m)?[jt]s$/.test(path)) {
      for (const m of text.matchAll(/mongoose\.model\(\s*['"](\w+)['"]/g)) addEntity({ path, line: lineAt(text, m.index!), name: m[1], columns: [], source: 'Mongoose' });
      for (const m of text.matchAll(/@Entity\([^)]*\)\s*(?:export\s+)?class\s+(\w+)/g)) addEntity({ path, line: lineAt(text, m.index!), name: m[1], columns: [], source: 'TypeORM' });
      for (const m of text.matchAll(/(?:pgTable|sqliteTable|mysqlTable)\(\s*['"](\w+)['"]/g)) addEntity({ path, line: lineAt(text, m.index!), name: m[1], columns: [], source: 'Drizzle' });
    }
  }
  const names = new Set(entities.map((e) => e.name.toLowerCase()));
  return { entities, relations: relations.filter((r) => names.has(r.from.toLowerCase()) && names.has(r.to.toLowerCase())) };
}

// ---------------------------------------------------------------------------
// Settings the code reads
// ---------------------------------------------------------------------------

export interface EnvVar {
  name: string;
  refs: Ref[];
  documented: boolean;
}

export function extractEnv(files: Files): EnvVar[] {
  const map = new Map<string, EnvVar>();
  const add = (name: string, path: string, line: number, documented = false) => {
    if (!/^[A-Z][A-Z0-9_]{1,}$/.test(name)) return;
    // The shell's own variables are not settings of the project.
    if (!documented && /^(PATH|HOME|PWD|USER|SHELL|CI|TERM|HOSTNAME|GITHUB_TOKEN|GITHUB_\w+|RUNNER_\w+)$/.test(name)) return;
    const v = map.get(name) ?? { name, refs: [], documented: false };
    if (v.refs.length < 4) v.refs.push({ path, line });
    v.documented ||= documented;
    map.set(name, v);
  };
  const patterns = [
    /process\.env\.([A-Z][A-Z0-9_]+)/g,
    /process\.env\[\s*['"]([A-Z][A-Z0-9_]+)['"]\s*\]/g,
    /import\.meta\.env\.([A-Z][A-Z0-9_]+)/g,
    /Deno\.env\.get\(\s*['"]([A-Z][A-Z0-9_]+)['"]/g,
    /os\.(?:environ\.get|getenv)\(\s*['"]([A-Z][A-Z0-9_]+)['"]/g,
    /os\.environ\[\s*['"]([A-Z][A-Z0-9_]+)['"]\s*\]/g,
    /String\.fromEnvironment\(\s*['"]([A-Z][A-Z0-9_]+)['"]/g,
    /System\.getenv\(\s*"([A-Z][A-Z0-9_]+)"/g,
    /os\.Getenv\(\s*"([A-Z][A-Z0-9_]+)"/g,
    /ENV\[\s*['"]([A-Z][A-Z0-9_]+)['"]\s*\]/g,
    /\$\{\{\s*(?:secrets|vars)\.([A-Z][A-Z0-9_]+)\s*\}\}/g,
  ];
  for (const [path, text] of files) {
    if (isEnvExample(path)) {
      for (const name of envNames(text)) add(name, path, 1, true);
      continue;
    }
    for (const re of patterns) for (const m of text.matchAll(re)) add(m[1], path, lineAt(text, m.index!));
  }
  return [...map.values()].sort((a, b) => a.name.localeCompare(b.name)).slice(0, 150);
}

// ---------------------------------------------------------------------------
// CI/CD, containers, deployment
// ---------------------------------------------------------------------------

export interface Workflow extends Ref {
  name: string;
  triggers: string[];
  jobs: { name: string; steps: string[] }[];
}

export function extractWorkflows(files: Files): Workflow[] {
  const out: Workflow[] = [];
  for (const [path, text] of files) {
    if (!/^\.github\/workflows\/[^/]+\.ya?ml$/.test(path) && !/(^|\/)\.gitlab-ci\.yml$/.test(path)) continue;
    const name = /^name:\s*(.+)$/m.exec(text)?.[1]?.replace(/['"]/g, '').trim() ?? path.split('/').pop()!;
    const triggers: string[] = [];
    const on = /^['"]?on['"]?:[ \t]*(.*)\n((?:[ \t]+.*\n|[ \t]*\n)*)/m.exec(text);
    if (on) {
      if (on[1].trim()) triggers.push(...on[1].replace(/[[\]]/g, '').split(',').map((s) => s.trim()).filter(Boolean));
      for (const m of on[2].matchAll(/^ {2}(\w[\w_]*):/gm)) triggers.push(m[1]);
    }
    const jobs: { name: string; steps: string[] }[] = [];
    const jobsBlock = /^jobs:\s*\n([\s\S]*)/m.exec(text)?.[1] ?? '';
    const jobHeads = [...jobsBlock.matchAll(/^ {2}([\w-]+):\s*$/gm)];
    jobHeads.forEach((h, i) => {
      const body = jobsBlock.slice(h.index!, jobHeads[i + 1]?.index ?? jobsBlock.length);
      const steps: string[] = [];
      for (const s of body.matchAll(/-\s+(?:name:\s*(.+)|uses:\s*(\S+)|run:\s*(?!\|)(.+))/g)) {
        steps.push((s[1] ?? (s[2] ? `uses ${s[2]}` : `run: ${s[3]}`)).replace(/['"]/g, '').trim().slice(0, 120));
        if (steps.length >= 14) break;
      }
      jobs.push({ name: h[1], steps });
    });
    out.push({ path, line: 1, name, triggers: [...new Set(triggers)], jobs: jobs.slice(0, 12) });
  }
  return out;
}

export interface Container extends Ref {
  kind: 'Dockerfile' | 'Compose service';
  name: string;
  details: string[];
}

export function extractContainers(files: Files): Container[] {
  const out: Container[] = [];
  for (const [path, text] of files) {
    const file = path.split('/').pop()!;
    if (/^Dockerfile|\.dockerfile$/i.test(file)) {
      const d: string[] = [];
      for (const m of text.matchAll(/^\s*(FROM|EXPOSE|CMD|ENTRYPOINT|WORKDIR)\s+(.+)$/gim)) d.push(`${m[1].toUpperCase()} ${m[2].trim().slice(0, 100)}`);
      out.push({ path, line: 1, kind: 'Dockerfile', name: path.includes('/') ? path.split('/').slice(-2, -1)[0] : 'app', details: d.slice(0, 10) });
    } else if (/^(docker-compose[^/]*|compose)\.ya?ml$/.test(file)) {
      const services = /^services:\s*\n([\s\S]*?)(?=^\S|$(?![\s\S]))/m.exec(text)?.[1] ?? '';
      const heads = [...services.matchAll(/^ {2}([\w.-]+):\s*$/gm)];
      heads.forEach((h, i) => {
        const body = services.slice(h.index!, heads[i + 1]?.index ?? services.length);
        const d: string[] = [];
        const image = /^\s+image:\s*(.+)$/m.exec(body)?.[1];
        if (image) d.push(`image ${image.trim()}`);
        if (/^\s+build:/m.test(body)) d.push('built from this repository');
        for (const p of body.matchAll(/^\s+-\s*["']?(\d+:\d+)["']?/gm)) d.push(`port ${p[1]}`);
        const dep = /^\s+depends_on:\s*\n((?:\s+-.*\n)+)/m.exec(body)?.[1];
        if (dep) d.push(`depends on ${[...dep.matchAll(/-\s*(\S+)/g)].map((x) => x[1]).join(', ')}`);
        out.push({ path, line: lineAt(text, text.indexOf(h[0])), kind: 'Compose service', name: h[1], details: d });
      });
    }
  }
  return out;
}

export interface DeployTarget extends Ref {
  platform: string;
  detail: string;
}

export function extractDeployment(files: Files, paths: string[]): DeployTarget[] {
  const out: DeployTarget[] = [];
  const add = (platform: string, path: string, line: number, detail: string) => {
    if (!out.some((o) => o.platform === platform && o.path === path)) out.push({ platform, path, line, detail });
  };
  const byFile: [RegExp, string, string][] = [
    [/(^|\/)vercel\.json$/, 'Vercel', 'Vercel project configuration'],
    [/(^|\/)netlify\.toml$/, 'Netlify', 'Netlify build and redirects'],
    [/(^|\/)wrangler\.(toml|jsonc?)$/, 'Cloudflare Workers', 'Worker configuration'],
    [/(^|\/)fly\.toml$/, 'Fly.io', 'Fly app configuration'],
    [/(^|\/)render\.yaml$/, 'Render', 'Render blueprint'],
    [/(^|\/)Procfile$/, 'Heroku-style Procfile', 'Process types'],
    [/(^|\/)app\.ya?ml$/, 'Google App Engine', 'App Engine configuration'],
    [/(^|\/)firebase\.json$/, 'Firebase Hosting', 'Firebase project configuration'],
    [/(^|\/)serverless\.ya?ml$/, 'Serverless Framework', 'Function deployment'],
    [/(^|\/)supabase\/config\.toml$/, 'Supabase', 'Supabase project: database, auth, functions'],
    [/\.tf$/, 'Terraform', 'Infrastructure as code'],
    [/(^|\/)Chart\.yaml$/, 'Kubernetes (Helm)', 'Helm chart'],
  ];
  for (const p of paths) for (const [re, platform, detail] of byFile) if (re.test(p)) add(platform, p, 1, detail);
  const inWorkflow: [RegExp, string][] = [
    [/pages\s+deploy|cloudflare\/pages-action/i, 'Cloudflare Pages'],
    [/wrangler(-action)?[^\n]*deploy|cloudflare\/wrangler-action/i, 'Cloudflare Workers'],
    [/vercel\s+(deploy|--prod)|amondnet\/vercel-action/i, 'Vercel'],
    [/netlify\s+deploy|nwtgck\/actions-netlify/i, 'Netlify'],
    [/supabase\s+(functions\s+deploy|db\s+push)/i, 'Supabase'],
    [/firebase\s+deploy|FirebaseExtended\/action-hosting-deploy/i, 'Firebase Hosting'],
    [/flyctl\s+deploy|superfly\/flyctl-actions/i, 'Fly.io'],
    [/aws-actions\/|aws\s+(s3|ecs|lambda|cloudformation)/i, 'AWS'],
    [/google-github-actions\/(deploy|auth)|gcloud\s+(run|app)\s+deploy/i, 'Google Cloud'],
    [/azure\/(webapps-deploy|login)/i, 'Azure'],
    [/docker\/build-push-action|docker\s+push/i, 'Container registry'],
    [/kubectl\s+apply|helm\s+(upgrade|install)/i, 'Kubernetes'],
    [/actions\/deploy-pages|peaceiris\/actions-gh-pages/i, 'GitHub Pages'],
    [/railway\s+up/i, 'Railway'],
    [/heroku\s+|akhileshns\/heroku-deploy/i, 'Heroku'],
  ];
  for (const [path, text] of files) {
    if (!/^\.github\/workflows\//.test(path) && !/\.gitlab-ci\.yml$/.test(path)) continue;
    // `wrangler pages deploy` is Pages, not Workers, though it says wrangler.
    const pages = /pages\s+deploy|cloudflare\/pages-action/i.test(text);
    for (const [re, platform] of inWorkflow) {
      if (platform === 'Cloudflare Workers' && pages) continue;
      const m = re.exec(text);
      if (m) add(platform, path, lineAt(text, m.index), 'Deployed by this workflow');
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

export function extractEntryPoints(files: Files, paths: string[]): Ref[] {
  const out: Ref[] = [];
  const add = (path: string, line = 1) => {
    if (paths.includes(path) && !out.some((o) => o.path === path)) out.push({ path, line });
  };
  for (const [path, text] of files) {
    if (path.endsWith('package.json')) {
      try {
        const j = JSON.parse(text);
        const dir = path.replace(/package\.json$/, '');
        for (const m of [j.main, j.module, typeof j.bin === 'string' ? j.bin : null]) if (typeof m === 'string') add(dir + m.replace(/^\.\//, ''));
        const start = String(j.scripts?.start ?? j.scripts?.dev ?? '');
        const f = /(?:node|ts-node|tsx|nodemon|bun|deno run[^ ]*)\s+([\w./-]+\.[cm]?[jt]s)/.exec(start);
        if (f) add(dir + f[1].replace(/^\.\//, ''));
      } catch (_) { /* reported elsewhere */ }
    }
    if (/if\s+__name__\s*==\s*['"]__main__['"]/.test(text)) add(path, lineAt(text, text.search(/if\s+__name__/)));
    if (/\.go$/.test(path) && /^package main$/m.test(text) && /func main\(\)/.test(text)) add(path, lineAt(text, text.indexOf('func main()')));
    if (/\.(java|kt)$/.test(path) && /@SpringBootApplication|static void main\(|fun main\(/.test(text)) add(path);
    if (/\.dart$/.test(path) && /void main\(/.test(text) && /(^|\/)(lib|bin)\//.test(path)) add(path, lineAt(text, text.search(/void main\(/)));
    if (/\.rs$/.test(path) && /fn main\(\)/.test(text)) add(path, lineAt(text, text.indexOf('fn main()')));
    if (/\.(c|m)?[jt]sx?$/.test(path) && /(createRoot|ReactDOM\.render|createApp\(|bootstrapApplication|platformBrowserDynamic|app\.listen\(|serve\(\{|Deno\.serve\()/.test(text)) {
      add(path, lineAt(text, text.search(/(createRoot|ReactDOM\.render|createApp\(|bootstrapApplication|platformBrowserDynamic|app\.listen\(|serve\(\{|Deno\.serve\()/)));
    }
  }
  for (const p of paths) if (/(^|\/)(manage\.py|wsgi\.py|asgi\.py|main\.py|app\.py|server\.[jt]s|index\.html)$/.test(p) && p.split('/').length <= 3) add(p);
  return out.slice(0, 25);
}

// ---------------------------------------------------------------------------
// Imports between modules
// ---------------------------------------------------------------------------

/// Edges between files by their import statements, resolved to repository
/// paths where they are relative (or the package's own name, for Dart).
export function extractImports(files: Files, paths: Set<string>): [string, string][] {
  const edges: [string, string][] = [];
  const pubName = [...files].find(([p]) => p === 'pubspec.yaml')?.[1].match(/^name:\s*(\S+)/m)?.[1];
  const resolve = (from: string, spec: string): string | null => {
    const base = from.split('/').slice(0, -1);
    for (const part of spec.split('/')) {
      if (part === '..') base.pop();
      else if (part !== '.') base.push(part);
    }
    const p = base.join('/');
    for (const cand of [p, `${p}.ts`, `${p}.tsx`, `${p}.js`, `${p}.jsx`, `${p}.mjs`, `${p}/index.ts`, `${p}/index.tsx`, `${p}/index.js`, `${p}.py`, `${p}/__init__.py`]) {
      if (paths.has(cand)) return cand;
    }
    return null;
  };
  for (const [path, text] of files) {
    let specs: string[] = [];
    if (/\.(c|m)?[jt]sx?$|\.vue$|\.svelte$/.test(path)) {
      specs = [...text.matchAll(/(?:import\s[^'"]*?from\s*|import\s*\(\s*|require\(\s*|export\s[^'"]*?from\s*)['"](\.{1,2}\/[^'"]+)['"]/g)].map((m) => m[1]);
      for (const s of specs) {
        const r = resolve(path, s);
        if (r) edges.push([path, r]);
      }
    } else if (/\.dart$/.test(path)) {
      for (const m of text.matchAll(/^(?:import|export)\s+['"]([^'"]+)['"]/gm)) {
        const s = m[1];
        let r: string | null = null;
        if (pubName && s.startsWith(`package:${pubName}/`)) r = `lib/${s.slice(pubName.length + 9)}`;
        else if (!s.includes(':')) r = resolve(path, s);
        if (r && paths.has(r)) edges.push([path, r]);
      }
    } else if (/\.py$/.test(path)) {
      for (const m of text.matchAll(/^(?:from\s+(\.*[\w.]*)\s+import|import\s+([\w.]+))/gm)) {
        const mod = m[1] ?? m[2];
        if (!mod) continue;
        const dots = /^\.*/.exec(mod)![0].length;
        let base: string[];
        if (dots) {
          base = path.split('/').slice(0, -dots);
        } else {
          base = [];
        }
        const rel = [...base, ...mod.slice(dots).split('.').filter(Boolean)].join('/');
        for (const cand of [`${rel}.py`, `${rel}/__init__.py`]) {
          if (paths.has(cand)) {
            edges.push([path, cand]);
            break;
          }
        }
      }
    } else if (/\.go$/.test(path)) {
      const mod = [...files].find(([p]) => p === 'go.mod')?.[1].match(/^module\s+(\S+)/m)?.[1];
      if (!mod) continue;
      for (const m of text.matchAll(/"([^"]+)"/g)) {
        if (m[1].startsWith(`${mod}/`)) {
          const dir = m[1].slice(mod.length + 1);
          const target = [...paths].find((p) => p.startsWith(`${dir}/`) && p.endsWith('.go'));
          if (target) edges.push([path, target]);
        }
      }
    }
  }
  return edges;
}

// ---------------------------------------------------------------------------
// Code quality signals
// ---------------------------------------------------------------------------

export interface Quality {
  sourceFiles: number;
  testFiles: number;
  todoCount: number;
  largestFiles: { path: string; lines: number }[];
  linters: string[];
  typeChecked: boolean;
  ciRunsTests: boolean;
  hasLicense: boolean;
  hasReadme: boolean;
  hasContributing: boolean;
  hasSecurityPolicy: boolean;
  dependencyUpdates: boolean;
  lockfiles: string[];
}

export function extractQuality(files: Files, paths: string[], lockfiles: string[]): Quality {
  const source = paths.filter((p) => /\.((c|m)?[jt]sx?|py|go|rs|dart|java|kt|swift|cs|rb|php|ex|vue|svelte)$/.test(p));
  const tests = source.filter((p) => /(^|\/)(test|tests|__tests__|spec|e2e|integration_test)\/|[._-](test|spec)\.|_test\.(go|dart|py)$|^test_.*\.py$|\/test_[^/]*\.py$/.test(p));
  let todo = 0;
  const sizes: { path: string; lines: number }[] = [];
  for (const [p, t] of files) {
    if (!source.includes(p)) continue;
    todo += (t.match(/\b(TODO|FIXME|HACK|XXX)\b/g) ?? []).length;
    sizes.push({ path: p, lines: t.split('\n').length });
  }
  const has = (re: RegExp) => paths.some((p) => re.test(p));
  const linters = [
    [/(^|\/)(\.eslintrc[^/]*|eslint\.config\.[cm]?js)$/, 'ESLint'],
    [/(^|\/)\.prettierrc/, 'Prettier'],
    [/(^|\/)(ruff\.toml|\.flake8|\.pylintrc)$/, 'Python linter'],
    [/(^|\/)analysis_options\.yaml$/, 'Dart analyzer rules'],
    [/(^|\/)\.golangci\.ya?ml$/, 'golangci-lint'],
    [/(^|\/)(rustfmt|clippy)\.toml$/, 'Rust lints'],
    [/(^|\/)\.editorconfig$/, 'EditorConfig'],
  ].filter(([re]) => has(re as RegExp)).map(([, n]) => n as string);
  const workflows = [...files].filter(([p]) => /^\.github\/workflows\//.test(p)).map(([, t]) => t).join('\n');
  return {
    sourceFiles: source.length,
    testFiles: tests.length,
    todoCount: todo,
    largestFiles: sizes.sort((a, b) => b.lines - a.lines).slice(0, 5),
    linters,
    typeChecked: has(/(^|\/)tsconfig[^/]*\.json$/) || has(/\.(dart|go|rs|java|kt|cs|swift)$/) || has(/(^|\/)(mypy\.ini|pyrightconfig\.json)$/),
    ciRunsTests: /\b(npm|pnpm|yarn|bun)\s+(run\s+)?test|pytest|flutter test|go test|cargo test|mvn\s+.*test|gradlew?\s+.*test|deno test|vitest|jest|playwright test/i.test(workflows),
    hasLicense: has(/^(LICENSE|LICENCE|COPYING)(\.\w+)?$/i),
    hasReadme: has(/^README/i),
    hasContributing: has(/(^|\/)CONTRIBUTING/i),
    hasSecurityPolicy: has(/(^|\/)SECURITY\.md$/i),
    dependencyUpdates: has(/^\.github\/dependabot\.ya?ml$/) || has(/(^|\/)renovate\.json5?$/),
    lockfiles,
  };
}
