// What a repository is built with, from what it declares.
//
// Dependencies come from the manifests themselves (package.json, pubspec.yaml,
// requirements.txt and the rest), parsed rather than guessed. Technologies are
// then matched by rule: a dependency or a configuration file that only exists
// for that technology makes it *confirmed*; a mention in source alone (an
// import of a cloud SDK in one file, say) makes it *inferred*. Every result
// carries the paths it was found in, so nothing in the report is unsupported.

export interface Dependency {
  name: string;
  version: string;
  dev: boolean;
  ecosystem: string;
  manifest: string;
}

export interface Tech {
  name: string;
  category: string;
  confidence: 'confirmed' | 'inferred';
  evidence: string[];
  purpose: string;
}

export type Files = Map<string, string>;

// ---------------------------------------------------------------------------
// Manifests
// ---------------------------------------------------------------------------

export function parseManifests(files: Files): { deps: Dependency[]; scripts: Record<string, Record<string, string>> } {
  const deps: Dependency[] = [];
  const scripts: Record<string, Record<string, string>> = {};
  const add = (ecosystem: string, manifest: string, name: string, version: string, dev = false) => {
    name = name.trim();
    if (name && !/[\s{}]/.test(name)) deps.push({ name, version: version.trim() || '*', dev, ecosystem, manifest });
  };
  for (const [path, text] of files) {
    const name = path.split('/').pop()!;
    try {
      if (name === 'package.json') {
        const j = JSON.parse(text);
        for (const [k, v] of Object.entries(j.dependencies ?? {})) add('npm', path, k, String(v));
        for (const [k, v] of Object.entries(j.devDependencies ?? {})) add('npm', path, k, String(v), true);
        for (const [k, v] of Object.entries(j.peerDependencies ?? {})) add('npm', path, k, String(v));
        if (j.scripts && typeof j.scripts === 'object') scripts[path] = j.scripts;
      } else if (name === 'composer.json') {
        const j = JSON.parse(text);
        for (const [k, v] of Object.entries(j.require ?? {})) add('composer', path, k, String(v));
        for (const [k, v] of Object.entries(j['require-dev'] ?? {})) add('composer', path, k, String(v), true);
      } else if (/^deno\.jsonc?$/.test(name)) {
        const j = JSON.parse(text.replace(/^\s*\/\/.*$/gm, ''));
        for (const [k, v] of Object.entries(j.imports ?? {})) add('deno', path, k, String(v));
        if (j.tasks) scripts[path] = j.tasks;
      } else if (/^requirements[^/]*\.txt$/.test(name)) {
        const dev = /dev|test/.test(name);
        for (const line of text.split('\n')) {
          const m = /^\s*([A-Za-z0-9_.\-[\]]+)\s*([<>=!~].*)?$/.exec(line.replace(/#.*/, ''));
          if (m && !line.trim().startsWith('-')) add('pypi', path, m[1].replace(/\[.*\]/, ''), m[2] ?? '', dev);
        }
      } else if (name === 'pyproject.toml') {
        // PEP 621 `dependencies = [...]` and optional groups, and Poetry tables.
        // To the closing bracket on its own line: an extra like
        // "fastapi[standard]" has a ']' of its own.
        const arr = /^\s*dependencies\s*=\s*\[([\s\S]*?)^\s*\]/m.exec(text) ?? /^\s*dependencies\s*=\s*\[(.*)\]\s*$/m.exec(text);
        for (const m of (arr?.[1] ?? '').matchAll(/["']([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?\s*([^"']*)["']/g)) add('pypi', path, m[1], m[2]);
        for (const block of text.matchAll(/^\[tool\.poetry\.(?:group\.\w+\.)?(dev-)?dependencies\]\s*\n([\s\S]*?)(?=^\[|$(?![\s\S]))/gm)) {
          for (const m of block[2].matchAll(/^\s*([A-Za-z0-9_.-]+)\s*=\s*(.+)$/gm)) {
            if (m[1] !== 'python') add('pypi', path, m[1], m[2].replace(/["{}]/g, ''), !!block[1] || /group\.(dev|test)/.test(block[0]));
          }
        }
        for (const block of text.matchAll(/^\[project\.optional-dependencies\]\s*\n([\s\S]*?)(?=^\[|$(?![\s\S]))/gm)) {
          for (const m of block[1].matchAll(/["']([A-Za-z0-9_.-]+)[^"']*["']/g)) add('pypi', path, m[1], '', true);
        }
      } else if (name === 'Pipfile') {
        for (const block of text.matchAll(/^\[(dev-)?packages\]\s*\n([\s\S]*?)(?=^\[|$(?![\s\S]))/gm)) {
          for (const m of block[2].matchAll(/^\s*([A-Za-z0-9_.-]+)\s*=\s*(.+)$/gm)) add('pypi', path, m[1], m[2].replace(/["{}]/g, ''), !!block[1]);
        }
      } else if (name === 'setup.py') {
        const arr = /install_requires\s*=\s*\[([\s\S]*?)\]/.exec(text);
        for (const m of (arr?.[1] ?? '').matchAll(/["']([A-Za-z0-9_.-]+)\s*([^"']*)["']/g)) add('pypi', path, m[1], m[2]);
      } else if (name === 'pubspec.yaml') {
        for (const [section, dev] of [['dependencies', false], ['dev_dependencies', true]] as const) {
          const block = new RegExp(`^${section}:\\s*\\n((?:[ \\t]+.*\\n?|\\s*\\n)*)`, 'm').exec(text);
          for (const m of (block?.[1] ?? '').matchAll(/^ {2}([A-Za-z0-9_]+):\s*(.*)$/gm)) add('pub', path, m[1], m[2] || 'sdk', dev);
        }
      } else if (name === 'go.mod') {
        for (const m of text.matchAll(/^\s*(?:require\s+)?([a-z0-9.-]+\.[a-z]+\/[^\s]+)\s+(v[^\s]+)/gm)) add('go', path, m[1], m[2], /\/\/ indirect/.test(m[0]));
      } else if (name === 'Cargo.toml') {
        for (const block of text.matchAll(/^\[(dev-)?dependencies\]\s*\n([\s\S]*?)(?=^\[|$(?![\s\S]))/gm)) {
          for (const m of block[2].matchAll(/^\s*([A-Za-z0-9_-]+)\s*=\s*(.+)$/gm)) add('cargo', path, m[1], m[2].replace(/["{}]/g, ''), !!block[1]);
        }
      } else if (name === 'pom.xml') {
        for (const m of text.matchAll(/<dependency>\s*<groupId>([^<]+)<\/groupId>\s*<artifactId>([^<]+)<\/artifactId>(?:\s*<version>([^<]+)<\/version>)?(?:[\s\S]*?<scope>([^<]+)<\/scope>)?[\s\S]*?<\/dependency>/g)) {
          add('maven', path, `${m[1]}:${m[2]}`, m[3] ?? '', m[4] === 'test');
        }
      } else if (/^build\.gradle(\.kts)?$/.test(name)) {
        for (const m of text.matchAll(/^\s*(implementation|api|compileOnly|runtimeOnly|kapt|ksp|testImplementation|androidTestImplementation|annotationProcessor)\s*\(?\s*["']([^:"']+:[^:"']+)(?::([^"']+))?["']/gm)) {
          add('gradle', path, m[2], m[3] ?? '', /test/i.test(m[1]));
        }
        for (const m of text.matchAll(/id\s*\(?\s*["']([a-z0-9.-]+)["']/g)) add('gradle-plugin', path, m[1], '');
      } else if (name === 'Gemfile') {
        for (const m of text.matchAll(/^\s*gem\s+["']([^"']+)["'](?:\s*,\s*["']([^"']+)["'])?/gm)) add('rubygems', path, m[1], m[2] ?? '');
      } else if (/\.csproj$/.test(name)) {
        for (const m of text.matchAll(/<PackageReference\s+Include="([^"]+)"(?:\s+Version="([^"]+)")?/g)) add('nuget', path, m[1], m[2] ?? '');
      } else if (name === 'mix.exs') {
        for (const m of text.matchAll(/\{:([a-z_]+),\s*"([^"]+)"/g)) add('hex', path, m[1], m[2]);
      }
    } catch (_) {
      // A manifest that does not parse is reported by its absence from the
      // dependency list, not by failing the analysis.
    }
  }
  return { deps, scripts };
}

// ---------------------------------------------------------------------------
// Technology rules
// ---------------------------------------------------------------------------

interface Rule {
  name: string;
  category: string;
  purpose: string;
  /** Dependency names (exact, or a regex) that confirm it. */
  deps?: (string | RegExp)[];
  /** Paths whose existence confirms it. */
  files?: RegExp;
  /** [path filter, content] whose match infers it. */
  code?: [RegExp, RegExp];
}

const R = (name: string, category: string, purpose: string, extra: Omit<Rule, 'name' | 'category' | 'purpose'>): Rule => ({ name, category, purpose, ...extra });
const JS = /\.(c|m)?[jt]sx?$/;
const PY = /\.py$/;

export const RULES: Rule[] = [
  // Frontend
  R('React', 'Frontend', 'Builds the user interface from components', { deps: ['react'] }),
  R('Next.js', 'Frontend', 'React framework with routing, server rendering and API routes', { deps: ['next'], files: /(^|\/)next\.config\.[cm]?[jt]s$/ }),
  R('Vue', 'Frontend', 'Builds the user interface from reactive components', { deps: ['vue'] }),
  R('Nuxt', 'Frontend', 'Vue framework with routing and server rendering', { deps: ['nuxt'], files: /nuxt\.config\.[jt]s$/ }),
  R('Angular', 'Frontend', 'Component framework for the user interface', { deps: ['@angular/core'], files: /(^|\/)angular\.json$/ }),
  R('Svelte', 'Frontend', 'Compiles components into small, fast UI code', { deps: ['svelte'] }),
  R('SvelteKit', 'Frontend', 'Svelte framework with routing and server rendering', { deps: ['@sveltejs/kit'] }),
  R('Astro', 'Frontend', 'Content-first site framework', { deps: ['astro'] }),
  R('Remix', 'Frontend', 'React framework built on web standards', { deps: [/^@remix-run\//] }),
  R('Solid', 'Frontend', 'Reactive UI library', { deps: ['solid-js'] }),
  R('Flutter', 'Frontend', 'One codebase for web, mobile and desktop UIs', { deps: ['flutter'], code: [/\.dart$/, /package:flutter\//] }),
  R('React Native', 'Mobile', 'Native mobile apps written in React', { deps: ['react-native'] }),
  R('Expo', 'Mobile', 'Toolchain and services for React Native apps', { deps: ['expo'] }),
  R('SwiftUI', 'Mobile', 'Apple’s declarative UI framework', { code: [/\.swift$/, /import SwiftUI/] }),
  R('Jetpack Compose', 'Mobile', 'Android’s declarative UI toolkit', { deps: [/^androidx\.compose/] }),
  R('Electron', 'Desktop', 'Desktop apps built with web technology', { deps: ['electron'] }),
  R('Tauri', 'Desktop', 'Small desktop apps with a web UI and a Rust core', { deps: [/^@tauri-apps\//, 'tauri'] }),
  // Styling and UI kits
  R('Tailwind CSS', 'Styling', 'Utility classes for styling', { deps: ['tailwindcss'], files: /tailwind\.config\.[cm]?[jt]s$/ }),
  R('Material UI', 'Styling', 'Ready-made Material Design components', { deps: [/^@mui\//] }),
  R('Chakra UI', 'Styling', 'Accessible component library', { deps: ['@chakra-ui/react'] }),
  R('shadcn/ui', 'Styling', 'Copy-in components on Radix and Tailwind', { files: /(^|\/)components\.json$/, deps: [/^@radix-ui\//] }),
  R('styled-components', 'Styling', 'CSS written in JavaScript', { deps: ['styled-components', '@emotion/react'] }),
  R('Sass', 'Styling', 'CSS with variables and nesting', { deps: ['sass', 'node-sass'], files: /\.scss$/ }),
  R('Bootstrap', 'Styling', 'CSS framework and components', { deps: ['bootstrap', 'react-bootstrap'] }),
  // State and data fetching
  R('Redux', 'State management', 'One store for application state', { deps: ['redux', '@reduxjs/toolkit'] }),
  R('Zustand', 'State management', 'Small hook-based store', { deps: ['zustand'] }),
  R('TanStack Query', 'State management', 'Fetches, caches and refreshes server data', { deps: ['@tanstack/react-query', 'react-query'] }),
  R('Riverpod', 'State management', 'Providers for state and dependencies in Flutter', { deps: ['flutter_riverpod', 'riverpod', 'hooks_riverpod'] }),
  R('Bloc', 'State management', 'Event-driven state for Flutter', { deps: ['flutter_bloc', 'bloc'] }),
  R('Provider', 'State management', 'Inherited-widget state for Flutter', { deps: ['provider'] }),
  R('MobX', 'State management', 'Observable state', { deps: ['mobx', 'mobx_flutter'] }),
  R('Pinia', 'State management', 'Store for Vue', { deps: ['pinia'] }),
  R('GraphQL', 'API', 'Typed query language for the API', { deps: ['graphql', '@apollo/client', 'apollo-server', '@apollo/server', 'urql', 'graphene', 'strawberry-graphql'], files: /\.(graphql|gql)$/ }),
  R('tRPC', 'API', 'Typed API calls between TypeScript client and server', { deps: [/^@trpc\//] }),
  R('gRPC', 'API', 'Binary RPC between services', { deps: [/grpc/], files: /\.proto$/ }),
  R('Axios', 'API', 'HTTP client', { deps: ['axios'] }),
  R('go_router', 'Routing', 'URL-based navigation for Flutter', { deps: ['go_router'] }),
  R('React Router', 'Routing', 'Client-side routing for React', { deps: ['react-router', 'react-router-dom'] }),
  // Backend
  R('Node.js', 'Runtime', 'JavaScript runtime for the server and tooling', { files: /(^|\/)package\.json$/ }),
  R('Express', 'Backend', 'Minimal HTTP server for Node.js', { deps: ['express'] }),
  R('Fastify', 'Backend', 'Fast HTTP server for Node.js', { deps: ['fastify'] }),
  R('NestJS', 'Backend', 'Structured Node.js server framework', { deps: ['@nestjs/core'] }),
  R('Koa', 'Backend', 'Middleware-based Node.js server', { deps: ['koa'] }),
  R('Hono', 'Backend', 'Small web framework for edge runtimes', { deps: ['hono'] }),
  R('Deno', 'Runtime', 'Secure TypeScript runtime', { files: /(^|\/)deno\.jsonc?$/, code: [/\.ts$/, /Deno\.(serve|env)/] }),
  R('Bun', 'Runtime', 'Fast JavaScript runtime and toolkit', { files: /(^|\/)bun\.lockb?$|bunfig\.toml$/ }),
  R('Django', 'Backend', 'Batteries-included Python web framework', { deps: ['django', 'Django'], files: /(^|\/)manage\.py$/ }),
  R('Django REST Framework', 'Backend', 'REST APIs on Django', { deps: ['djangorestframework'] }),
  R('Flask', 'Backend', 'Minimal Python web framework', { deps: ['flask', 'Flask'] }),
  R('FastAPI', 'Backend', 'Typed, async Python APIs with automatic docs', { deps: ['fastapi'] }),
  R('Spring Boot', 'Backend', 'Java/Kotlin application framework', { deps: [/^org\.springframework\.boot/], code: [/\.(java|kt)$/, /@SpringBootApplication/] }),
  R('Ruby on Rails', 'Backend', 'Convention-based Ruby web framework', { deps: ['rails'] }),
  R('Laravel', 'Backend', 'PHP web framework', { deps: ['laravel/framework'] }),
  R('ASP.NET Core', 'Backend', '.NET web framework', { deps: [/^Microsoft\.AspNetCore/] }),
  R('Gin', 'Backend', 'HTTP framework for Go', { deps: ['github.com/gin-gonic/gin'] }),
  R('Echo', 'Backend', 'HTTP framework for Go', { deps: ['github.com/labstack/echo/v4'] }),
  R('Fiber', 'Backend', 'HTTP framework for Go', { deps: ['github.com/gofiber/fiber/v2'] }),
  R('Actix Web', 'Backend', 'HTTP framework for Rust', { deps: ['actix-web'] }),
  R('Axum', 'Backend', 'HTTP framework for Rust', { deps: ['axum'] }),
  R('Phoenix', 'Backend', 'Elixir web framework', { deps: ['phoenix'] }),
  R('Celery', 'Messaging', 'Background task queue for Python', { deps: ['celery'] }),
  R('BullMQ', 'Messaging', 'Redis-backed job queue for Node.js', { deps: ['bullmq', 'bull'] }),
  R('Kafka', 'Messaging', 'Event streaming', { deps: ['kafkajs', 'confluent-kafka', 'kafka-python'] }),
  R('RabbitMQ', 'Messaging', 'Message broker', { deps: ['amqplib', 'pika'] }),
  R('Socket.IO', 'Realtime', 'Two-way realtime messaging', { deps: ['socket.io', 'socket.io-client'] }),
  // Data
  R('PostgreSQL', 'Database', 'Relational database', { deps: ['pg', 'postgres', 'psycopg2', 'psycopg2-binary', 'psycopg', 'asyncpg', 'org.postgresql:postgresql', 'github.com/lib/pq', 'github.com/jackc/pgx/v5', 'npgsql'], code: [/\.(sql|ya?ml|toml|prisma)$/, /postgres(ql)?/i] }),
  R('MySQL', 'Database', 'Relational database', { deps: ['mysql', 'mysql2', 'pymysql', 'mysqlclient', 'mysql:mysql-connector-java', 'github.com/go-sql-driver/mysql'] }),
  R('SQLite', 'Database', 'Embedded relational database', { deps: ['sqlite3', 'better-sqlite3', 'sqflite', 'rusqlite'] }),
  R('MongoDB', 'Database', 'Document database', { deps: ['mongodb', 'mongoose', 'pymongo', 'motor', 'go.mongodb.org/mongo-driver'] }),
  R('Redis', 'Database', 'In-memory store for caching and queues', { deps: ['redis', 'ioredis', '@upstash/redis', 'github.com/redis/go-redis/v9'] }),
  R('Supabase', 'Backend-as-a-service', 'Postgres database, auth, storage and Edge Functions', { deps: ['@supabase/supabase-js', 'supabase_flutter', 'supabase', '@supabase/ssr'], files: /(^|\/)supabase\/config\.toml$/ }),
  R('Firebase', 'Backend-as-a-service', 'Google’s app platform (auth, database, messaging, hosting)', { deps: ['firebase', 'firebase-admin', 'firebase_core', 'firebase-functions'], files: /(^|\/)firebase\.json$/ }),
  R('Cloud Firestore', 'Database', 'Firebase’s document database', { deps: ['cloud_firestore', '@google-cloud/firestore'], code: [JS, /getFirestore\(/] }),
  R('DynamoDB', 'Database', 'AWS key-value database', { deps: ['@aws-sdk/client-dynamodb', 'aws-sdk'], code: [/\.(ts|js|py|ya?ml|tf)$/, /dynamodb/i] }),
  R('Elasticsearch', 'Database', 'Search engine', { deps: ['@elastic/elasticsearch', 'elasticsearch'] }),
  R('pgvector', 'Database', 'Vector similarity search in Postgres', { deps: ['pgvector'], code: [/\.sql$/, /\bvector\(\d+\)|create extension[^;]*vector/i] }),
  R('Prisma', 'ORM', 'Typed database client and migrations', { deps: ['prisma', '@prisma/client'], files: /schema\.prisma$/ }),
  R('Drizzle', 'ORM', 'Typed SQL query builder', { deps: ['drizzle-orm'] }),
  R('TypeORM', 'ORM', 'Entity-based ORM for TypeScript', { deps: ['typeorm'] }),
  R('Sequelize', 'ORM', 'ORM for Node.js', { deps: ['sequelize'] }),
  R('SQLAlchemy', 'ORM', 'Python SQL toolkit and ORM', { deps: ['sqlalchemy', 'SQLAlchemy'] }),
  R('Alembic', 'ORM', 'Database migrations for SQLAlchemy', { deps: ['alembic'], files: /alembic\.ini$/ }),
  R('Hibernate / JPA', 'ORM', 'Java persistence', { deps: [/hibernate|spring-boot-starter-data-jpa|jakarta\.persistence/] }),
  // Auth
  R('NextAuth.js / Auth.js', 'Auth', 'Sign-in for Next.js apps', { deps: ['next-auth', /^@auth\//] }),
  R('Passport', 'Auth', 'Authentication strategies for Node.js', { deps: ['passport'] }),
  R('JSON Web Tokens', 'Auth', 'Signed tokens that carry identity', { deps: ['jsonwebtoken', 'jose', 'pyjwt', 'PyJWT', 'djangorestframework-simplejwt', 'dart_jsonwebtoken', 'github.com/golang-jwt/jwt/v5'] }),
  R('Firebase Authentication', 'Auth', 'Hosted sign-in with email, Google and more', { deps: ['firebase_auth', 'firebase/auth'], code: [JS, /from ['"]firebase\/auth['"]/] }),
  R('Supabase Auth', 'Auth', 'Supabase’s hosted sign-in', { code: [/\.(ts|js|dart|tsx)$/, /\.auth\.(signIn|signUp|getUser|onAuthStateChange)/] }),
  R('Clerk', 'Auth', 'Hosted sign-in and user management', { deps: [/^@clerk\//] }),
  R('Auth0', 'Auth', 'Hosted identity platform', { deps: [/auth0/] }),
  R('Spring Security', 'Auth', 'Authentication and authorization for Spring', { deps: [/spring-boot-starter-security|spring-security/] }),
  R('Django auth', 'Auth', 'Django’s built-in users and sessions', { code: [PY, /django\.contrib\.auth/] }),
  R('Devise', 'Auth', 'Authentication for Rails', { deps: ['devise'] }),
  R('bcrypt', 'Auth', 'Password hashing', { deps: ['bcrypt', 'bcryptjs', 'passlib', 'argon2', 'argon2-cffi'] }),
  // AI / ML
  R('OpenAI API', 'AI/ML', 'Calls OpenAI models', { deps: ['openai'] }),
  R('Anthropic API', 'AI/ML', 'Calls Claude models', { deps: ['@anthropic-ai/sdk', 'anthropic'] }),
  R('LangChain', 'AI/ML', 'Composes LLM calls, tools and retrieval', { deps: [/^langchain/, /^@langchain\//] }),
  R('LlamaIndex', 'AI/ML', 'Retrieval over your own data for LLMs', { deps: [/^llama[-_]index/, 'llamaindex'] }),
  R('Hugging Face Transformers', 'AI/ML', 'Pretrained models', { deps: ['transformers', '@huggingface/transformers', '@xenova/transformers', '@huggingface/inference'] }),
  R('PyTorch', 'AI/ML', 'Deep learning framework', { deps: ['torch', 'pytorch'] }),
  R('TensorFlow', 'AI/ML', 'Machine learning framework', { deps: ['tensorflow', '@tensorflow/tfjs', 'tflite_flutter'] }),
  R('scikit-learn', 'AI/ML', 'Classical machine learning', { deps: ['scikit-learn', 'sklearn'] }),
  R('NumPy / pandas', 'AI/ML', 'Numerical and tabular data', { deps: ['numpy', 'pandas'] }),
  R('Groq / OpenAI-compatible LLM', 'AI/ML', 'LLM calls over the OpenAI-compatible API', { code: [/\.(ts|js|py)$/, /chat\/completions/] }),
  R('Vercel AI SDK', 'AI/ML', 'Streaming LLM responses in web apps', { deps: ['ai', /^@ai-sdk\//] }),
  // Testing and quality
  R('Jest', 'Testing', 'JavaScript test runner', { deps: ['jest'], files: /jest\.config\.[jt]s$/ }),
  R('Vitest', 'Testing', 'Vite-native test runner', { deps: ['vitest'] }),
  R('Playwright', 'Testing', 'Browser automation and end-to-end tests', { deps: ['@playwright/test', 'playwright'] }),
  R('Cypress', 'Testing', 'End-to-end browser tests', { deps: ['cypress'] }),
  R('Testing Library', 'Testing', 'Tests UI as a user uses it', { deps: [/^@testing-library\//] }),
  R('pytest', 'Testing', 'Python test runner', { deps: ['pytest'], files: /(^|\/)(pytest\.ini|conftest\.py)$/ }),
  R('JUnit', 'Testing', 'Java test framework', { deps: [/junit/] }),
  R('flutter_test', 'Testing', 'Flutter widget and unit tests', { deps: ['flutter_test'] }),
  R('ESLint', 'Code quality', 'Finds problems in JavaScript/TypeScript', { deps: ['eslint'], files: /(^|\/)(\.eslintrc[^/]*|eslint\.config\.[cm]?js)$/ }),
  R('Prettier', 'Code quality', 'Formats code consistently', { deps: ['prettier'], files: /(^|\/)\.prettierrc/ }),
  R('Ruff', 'Code quality', 'Fast Python linter', { deps: ['ruff'], files: /(^|\/)ruff\.toml$/ }),
  R('TypeScript', 'Language tooling', 'Types for JavaScript', { deps: ['typescript'], files: /(^|\/)tsconfig[^/]*\.json$/ }),
  // Build
  R('Vite', 'Build', 'Dev server and bundler', { deps: ['vite'], files: /vite\.config\.[jt]s$/ }),
  R('Webpack', 'Build', 'Module bundler', { deps: ['webpack'], files: /webpack\.config\.[jt]s$/ }),
  R('Turborepo', 'Build', 'Monorepo task runner', { deps: ['turbo'], files: /(^|\/)turbo\.json$/ }),
  R('Nx', 'Build', 'Monorepo build system', { files: /(^|\/)nx\.json$/ }),
  R('pnpm', 'Build', 'Package manager', { files: /(^|\/)pnpm-(lock|workspace)\.yaml$/ }),
  R('Yarn', 'Build', 'Package manager', { files: /(^|\/)yarn\.lock$/ }),
  R('Poetry', 'Build', 'Python packaging and dependencies', { code: [/pyproject\.toml$/, /\[tool\.poetry\]/] }),
  R('uv', 'Build', 'Python package manager', { files: /(^|\/)uv\.lock$/ }),
  R('Gradle', 'Build', 'JVM and Android build tool', { files: /(^|\/)build\.gradle(\.kts)?$/ }),
  R('Maven', 'Build', 'Java build tool', { files: /(^|\/)pom\.xml$/ }),
  R('Make', 'Build', 'Task runner', { files: /(^|\/)Makefile$/ }),
  // DevOps / CI
  R('Docker', 'DevOps', 'Packages the app into containers', { files: /(^|\/)(Dockerfile[^/]*|[^/]*\.dockerfile)$/ }),
  R('Docker Compose', 'DevOps', 'Runs several containers together', { files: /(^|\/)(docker-compose[^/]*|compose)\.ya?ml$/ }),
  R('Kubernetes', 'DevOps', 'Container orchestration', { code: [/\.ya?ml$/, /^kind:\s*(Deployment|StatefulSet|Ingress|Service)\b/m], files: /(^|\/)(k8s|kubernetes|helm|charts)\// }),
  R('Helm', 'DevOps', 'Packages Kubernetes manifests', { files: /(^|\/)Chart\.yaml$/ }),
  R('Terraform', 'DevOps', 'Infrastructure as code', { files: /\.tf$/ }),
  R('GitHub Actions', 'CI/CD', 'Runs checks and deploys on push', { files: /^\.github\/workflows\/[^/]+\.ya?ml$/ }),
  R('GitLab CI', 'CI/CD', 'GitLab pipelines', { files: /(^|\/)\.gitlab-ci\.yml$/ }),
  R('CircleCI', 'CI/CD', 'Hosted CI', { files: /^\.circleci\// }),
  R('Dependabot', 'CI/CD', 'Opens pull requests for outdated dependencies', { files: /^\.github\/dependabot\.ya?ml$/ }),
  // Hosting and cloud
  R('Vercel', 'Hosting', 'Hosts web front ends and serverless functions', { files: /(^|\/)vercel\.json$/, deps: ['vercel', '@vercel/analytics'] }),
  R('Netlify', 'Hosting', 'Hosts static sites and functions', { files: /(^|\/)netlify\.toml$/ }),
  R('Cloudflare', 'Hosting', 'Edge network, Workers and Pages', { files: /(^|\/)wrangler\.(toml|jsonc?)$/, deps: ['wrangler', '@cloudflare/workers-types'], code: [/\.ya?ml$/, /wrangler|cloudflare\/pages-action|cloudflare\/wrangler-action/] }),
  R('Fly.io', 'Hosting', 'Runs app containers near users', { files: /(^|\/)fly\.toml$/ }),
  R('Render', 'Hosting', 'Managed hosting for web services', { files: /(^|\/)render\.yaml$/ }),
  R('Heroku', 'Hosting', 'Managed app platform', { files: /(^|\/)(Procfile|app\.json)$/ }),
  R('Railway', 'Hosting', 'Managed app platform', { files: /(^|\/)railway\.(json|toml)$/ }),
  R('AWS', 'Cloud', 'Amazon Web Services', { deps: [/^@aws-sdk\//, 'aws-sdk', 'boto3', 'aws-cdk-lib', /^software\.amazon\.awssdk/], code: [/\.(tf|ya?ml)$/, /provider\s+"aws"|aws-actions\//] }),
  R('Google Cloud', 'Cloud', 'Google Cloud Platform', { deps: [/^@google-cloud\//, /^google-cloud-/], code: [/\.(tf|ya?ml)$/, /provider\s+"google"|google-github-actions\//] }),
  R('Azure', 'Cloud', 'Microsoft Azure', { deps: [/^@azure\//, /^azure-/], code: [/\.(tf|ya?ml)$/, /provider\s+"azurerm"|azure\/login/] }),
  R('Serverless Framework', 'Cloud', 'Deploys functions to cloud providers', { files: /(^|\/)serverless\.ya?ml$/ }),
  // Integrations
  R('Stripe', 'Payments', 'Takes payments', { deps: ['stripe', '@stripe/stripe-js'] }),
  R('Sentry', 'Monitoring', 'Error tracking', { deps: [/^@sentry\//, 'sentry-sdk', 'sentry_flutter'] }),
  R('PostHog', 'Monitoring', 'Product analytics', { deps: ['posthog-js', 'posthog-node', 'posthog'] }),
  R('Firebase Cloud Messaging', 'Integration', 'Push notifications', { deps: ['firebase_messaging'], code: [JS, /getMessaging\(/] }),
  R('SendGrid / Resend / Nodemailer', 'Integration', 'Sends email', { deps: ['@sendgrid/mail', 'resend', 'nodemailer'] }),
  R('Twilio', 'Integration', 'SMS and voice', { deps: ['twilio'] }),
  R('BeautifulSoup', 'Integration', 'Parses HTML for scraping', { deps: ['beautifulsoup4', 'bs4'] }),
  R('n8n', 'Integration', 'Workflow automation', { files: /(^|\/)n8n\// }),
];

/// Every technology the evidence supports.
export function detectTech(paths: string[], files: Files, deps: Dependency[]): Tech[] {
  const out: Tech[] = [];
  for (const rule of RULES) {
    const evidence = new Set<string>();
    let confirmed = false;
    for (const d of deps) {
      if (rule.deps?.some((p) => (typeof p === 'string' ? d.name === p || d.name.toLowerCase() === p.toLowerCase() : p.test(d.name)))) {
        evidence.add(d.manifest);
        confirmed = true;
      }
    }
    if (rule.files) {
      for (const p of paths) {
        if (rule.files.test(p)) {
          evidence.add(p);
          confirmed = true;
          if (evidence.size >= 6) break;
        }
      }
    }
    if (rule.code && evidence.size < 6) {
      const [where, what] = rule.code;
      for (const [p, text] of files) {
        if (!where.test(p)) continue;
        what.lastIndex = 0;
        const m = what.exec(text);
        if (m) {
          evidence.add(`${p}:${text.slice(0, m.index).split('\n').length}`);
          if (evidence.size >= 6) break;
        }
      }
    }
    if (evidence.size) {
      out.push({ name: rule.name, category: rule.category, confidence: confirmed ? 'confirmed' : 'inferred', evidence: [...evidence].slice(0, 6), purpose: rule.purpose });
    }
  }
  // Supabase Auth from code alone is noise unless Supabase itself is present.
  return out.filter((t) => t.name !== 'Supabase Auth' || out.some((o) => o.name === 'Supabase'));
}

/// What a dependency is for, when the rules know it.
export function purposeOf(dep: Dependency): string | null {
  for (const rule of RULES) {
    if (rule.deps?.some((p) => (typeof p === 'string' ? dep.name === p : p.test(dep.name)))) return `${rule.name}: ${rule.purpose}`;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Languages
// ---------------------------------------------------------------------------

const EXT: Record<string, string> = {
  ts: 'TypeScript', tsx: 'TypeScript', mts: 'TypeScript', cts: 'TypeScript', js: 'JavaScript', jsx: 'JavaScript', mjs: 'JavaScript', cjs: 'JavaScript',
  py: 'Python', go: 'Go', rs: 'Rust', dart: 'Dart', java: 'Java', kt: 'Kotlin', kts: 'Kotlin', swift: 'Swift', cs: 'C#', rb: 'Ruby',
  php: 'PHP', ex: 'Elixir', exs: 'Elixir', scala: 'Scala', c: 'C', h: 'C', cc: 'C++', cpp: 'C++', hpp: 'C++', vue: 'Vue', svelte: 'Svelte',
  sql: 'SQL', sh: 'Shell', ps1: 'PowerShell', html: 'HTML', css: 'CSS', scss: 'SCSS', lua: 'Lua', r: 'R', jl: 'Julia', sol: 'Solidity',
};

export function languageOf(path: string): string | null {
  const ext = path.split('.').pop()!.toLowerCase();
  return EXT[ext] ?? null;
}
