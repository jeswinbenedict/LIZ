// Which files of a repository are worth reading.
//
// The whole file list comes free with the tree; contents cost a request each
// and the analysis has a wall clock. So contents are read for what explains a
// project — manifests, build and deploy configuration, documentation,
// schemas, entry points, routes, then the rest of the source, shallowest
// first — within a count and a byte budget. Binaries, vendored and generated
// code, lock files and anything that looks like a secret are never read.

import type { TreeEntry } from './github.ts';

export const MAX_FILES = 180;
export const MAX_FILE_BYTES = 200_000;
export const MAX_TOTAL_BYTES = 3_000_000;

const SKIP_DIRS = new Set([
  'node_modules', '.git', 'dist', 'build', 'out', '.next', '.nuxt', '.svelte-kit', 'coverage',
  'vendor', 'third_party', 'third-party', 'Pods', '.dart_tool', '__pycache__', '.venv', 'venv',
  'env', 'target', 'bin', 'obj', '.gradle', '.idea', '.vscode', '.cache', 'tmp', '.turbo',
  'bower_components', 'jspm_packages', '.terraform', 'site-packages', '.mypy_cache', '.pytest_cache',
]);

const BINARY = /\.(png|jpe?g|gif|webp|avif|ico|bmp|tiff?|psd|svgz|mp[34]|m4a|wav|ogg|flac|webm|mov|avi|mkv|pdf|zip|gz|tgz|bz2|xz|7z|rar|jar|war|ear|class|so|dylib|dll|exe|bin|o|a|lib|wasm|pyc|pyo|ttf|otf|woff2?|eot|db|sqlite3?|parquet|pkl|pt|onnx|h5|npy|npz|keystore|jks|p12|pfx|der|crt|cer|iso|dmg|apk|aab|ipa)$/i;

const GENERATED = /(\.min\.(js|css)$|\.map$|\.g\.dart$|\.freezed\.dart$|\.pb\.go$|_pb2\.py$|\.generated\.)/i;

const LOCKFILE = /(^|\/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|poetry\.lock|Pipfile\.lock|Cargo\.lock|composer\.lock|Gemfile\.lock|pubspec\.lock|go\.sum|packages\.lock\.json|gradle\.lockfile|uv\.lock)$/i;

/// Files never to read: they hold, or are likely to hold, secrets. The
/// committed examples (.env.example and the like) are read for the names of
/// the settings a project needs; their values are not kept.
export function isSecretFile(path: string): boolean {
  const name = path.split('/').pop()!.toLowerCase();
  if (/^\.env(\.(example|sample|template|dist|defaults))$/.test(name)) return false;
  return (
    /^\.env(\..*)?$/.test(name) ||
    /\.(pem|key|p8|ppk|asc|gpg|kdbx)$/.test(name) ||
    /^(id_rsa|id_dsa|id_ecdsa|id_ed25519)(\.pub)?$/.test(name) ||
    /^(credentials|secrets?|service[-_]?account.*)\.(json|ya?ml|toml)$/.test(name) ||
    /^\.(npmrc|pypirc|netrc|htpasswd|dockercfg)$/.test(name) ||
    name === 'google-services.json' || name === 'googleservice-info.plist'
  );
}

export function isEnvExample(path: string): boolean {
  return /(^|\/)\.env\.(example|sample|template|dist|defaults)$/i.test(path);
}

/// Whether a path is anything we could read at all.
export function readable(e: TreeEntry): boolean {
  if (e.type !== 'blob') return false;
  const parts = e.path.split('/');
  if (parts.some((p) => SKIP_DIRS.has(p))) return false;
  if (BINARY.test(e.path) || GENERATED.test(e.path) || LOCKFILE.test(e.path)) return false;
  if (isSecretFile(e.path)) return false;
  if ((e.size ?? 0) > MAX_FILE_BYTES || (e.size ?? 0) === 0) return false;
  return true;
}

export function isLockfile(path: string): boolean {
  return LOCKFILE.test(path);
}

export function inSkippedDir(path: string): boolean {
  return path.split('/').some((p) => SKIP_DIRS.has(p));
}

const MANIFEST = /(^|\/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|setup\.py|setup\.cfg|Pipfile|pubspec\.yaml|go\.mod|Cargo\.toml|pom\.xml|build\.gradle(\.kts)?|settings\.gradle(\.kts)?|Gemfile|composer\.json|mix\.exs|deno\.jsonc?|.*\.csproj|Package\.swift|CMakeLists\.txt|Makefile|environment\.ya?ml)$/i;
const INFRA = /(^|\/)(Dockerfile[^/]*|[^/]*\.dockerfile|docker-compose[^/]*\.ya?ml|compose\.ya?ml|Procfile|vercel\.json|netlify\.toml|wrangler\.toml|fly\.toml|render\.yaml|app\.ya?ml|firebase\.json|serverless\.ya?ml|[^/]*\.tf|nginx[^/]*\.conf|config\.toml|turbo\.json|nx\.json|lerna\.json|tsconfig[^/]*\.json|vite\.config\.[jt]s|next\.config\.[cm]?[jt]s|nuxt\.config\.[jt]s|angular\.json|svelte\.config\.js|astro\.config\.mjs|webpack\.config\.[jt]s|tailwind\.config\.[cm]?[jt]s|babel\.config\.js|\.babelrc|jest\.config\.[jt]s|vitest\.config\.[jt]s|pytest\.ini|tox\.ini|analysis_options\.yaml|\.eslintrc[^/]*|eslint\.config\.[cm]?js|\.prettierrc[^/]*|ruff\.toml|manage\.py|alembic\.ini|prisma\/schema\.prisma|schema\.prisma|dependabot\.ya?ml|codeql[^/]*\.ya?ml)$/i;
const DOC = /(^|\/)(README[^/]*|ARCHITECTURE[^/]*|CONTRIBUTING[^/]*|SECURITY[^/]*|CHANGELOG[^/]*)$|(^|\/)docs?\/[^/]+\.(md|mdx|rst|txt)$/i;
const SCHEMA = /(^|\/)(migrations?|schema|schemas|db|database|models?|entities|prisma|sql)\/|\.(sql|prisma|graphql|gql|proto)$|openapi[^/]*\.(ya?ml|json)$|swagger[^/]*\.(ya?ml|json)$/i;
const ENTRY = /(^|\/)(main|index|app|server|wsgi|asgi|manage|program|application|bootstrap)\.(c|m)?(ts|tsx|js|jsx|py|go|rs|dart|java|kt|cs|rb|php|ex)$|(^|\/)cmd\/[^/]+\/main\.go$|Application\.(java|kt)$/i;
const ROUTES = /(^|\/)(routes?|router|routers|api|controllers?|handlers?|endpoints?|views|resolvers|functions)\//i;
const SOURCE = /\.(c|m)?(ts|tsx|js|jsx)$|\.(py|go|rs|dart|java|kt|kts|swift|cs|rb|php|ex|exs|scala|vue|svelte|astro|c|cc|cpp|h|hpp|sql|sh|ps1|lua|r|jl|zig|clj|hs|ml|fs|elm|sol)$/i;

/// How much a file explains, higher first.
export function priority(path: string): number {
  const depth = path.split('/').length - 1;
  if (isEnvExample(path)) return 95;
  if (/^\.github\/workflows\/[^/]+\.ya?ml$/i.test(path)) return 92;
  if (MANIFEST.test(path)) return 100 - Math.min(depth * 2, 10);
  if (INFRA.test(path)) return 88 - Math.min(depth * 2, 10);
  if (DOC.test(path)) return depth === 0 ? 90 : 60;
  if (SCHEMA.test(path) && SOURCE.test(path.replace(/\.(prisma|graphql|gql|proto)$/, '.sql'))) return 75 - Math.min(depth, 8);
  if (ENTRY.test(path)) return 72 - Math.min(depth, 8);
  if (ROUTES.test(path) && SOURCE.test(path)) return 66 - Math.min(depth, 8);
  if (/test|spec|__tests__|fixtures?|examples?|samples?|demo/i.test(path)) return SOURCE.test(path) ? 12 - Math.min(depth, 8) : 2;
  if (SOURCE.test(path)) return 40 - Math.min(depth * 3, 30);
  if (/\.(md|ya?ml|json|toml|ini|cfg|conf|xml|gradle|properties|txt)$/i.test(path)) return 20 - Math.min(depth * 2, 18);
  return 0;
}

/// The files to read, in order, within the count and byte budget.
export function selectFiles(entries: TreeEntry[]): TreeEntry[] {
  const candidates = entries
    .filter(readable)
    .map((e) => ({ e, p: priority(e.path) }))
    .filter((x) => x.p > 0)
    .sort((a, b) => b.p - a.p || a.e.path.length - b.e.path.length);
  const out: TreeEntry[] = [];
  let bytes = 0;
  for (const { e } of candidates) {
    if (out.length >= MAX_FILES) break;
    if (bytes + (e.size ?? 0) > MAX_TOTAL_BYTES) continue;
    out.push(e);
    bytes += e.size ?? 0;
  }
  return out;
}
