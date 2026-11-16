// Credentials that turn up in source, found and blanked.
//
// Every file is scanned before anything is kept: a match is reported by path
// and line, with the value replaced by a marker, and the stored copy (which
// Ask reads) carries the marker, never the value. Patterns are the providers'
// published formats, so a match is very likely real; the generic one for
// `password = "..."` needs a quoted value of some length and skips obvious
// placeholders.

export interface SecretFinding {
  path: string;
  line: number;
  kind: string;
  /** 'high': a credential; 'info': an identifier that is public by design. */
  severity: 'high' | 'info';
}

const PATTERNS: [string, RegExp][] = [
  // A real key has a body of base64 between the markers; code that only names
  // the markers (to strip them from a key it was given) does not.
  ['Private key', /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----(?:\\n|\s)+[A-Za-z0-9+/=]{40,}[A-Za-z0-9+/=\s\\n]*-----END [A-Z ]*PRIVATE KEY(?: BLOCK)?-----/g],
  ['AWS access key', /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g],
  ['GitHub token', /\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{60,255})\b/g],
  ['Slack token', /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g],
  ['Stripe secret key', /\b(?:sk|rk)_live_[A-Za-z0-9]{20,}\b/g],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/g],
  ['OpenAI key', /\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}\b/g],
  ['Anthropic key', /\bsk-ant-[A-Za-z0-9_-]{32,}\b/g],
  ['Groq key', /\bgsk_[A-Za-z0-9]{40,}\b/g],
  ['Twilio key', /\bSK[0-9a-fA-F]{32}\b/g],
  ['SendGrid key', /\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/g],
  ['Supabase secret key', /\bsb_secret_[A-Za-z0-9_-]{20,}\b/g],
  ['Connection string with password', /\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqps?):\/\/[^\s:/'"@]+:[^\s'"@/]{4,}@[^\s'"]+/g],
  // JWTs whose payload names a service or admin role: an anon key is public
  // by design, a service key is not.
  ['Service-role JWT', /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]*?(?:c2VydmljZV9yb2xl|InNlcnZpY2Vfcm9sZS)[A-Za-z0-9_-]*\.[A-Za-z0-9_-]{10,}\b/g],
];

const GENERIC = /\b((?:[A-Za-z_]*_)?(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key))\b\s*[:=]\s*(['"`])([^'"`\s]{8,})\2/gi;
const PLACEHOLDER = /^(?:x+|\*+|\.+|<.*>|\$\{.*\}|\{\{.*\}\}|secret|password|todo|none|null|undefined|process\.env.*|os\.environ.*|env\(.*)$|your[_-]|change[_-]?me|example|sample|placeholder|dummy|fake|demo|test|xxx/i;

/// A connection string's password that is a placeholder or a local default,
/// not a credential: `<db-password>`, `${PASSWORD}`, `postgres:postgres@localhost`.
function placeholderConnection(s: string): boolean {
  const m = /:\/\/([^:/@]+):([^@]+)@([^/:?\s'"]+)/.exec(s);
  if (!m) return false;
  const [, user, pass, host] = m;
  return /[<>{}$%]/.test(pass) || pass === user || /^(password|pass|secret|postgres|root|admin|example|changeme)$/i.test(pass) || /^(localhost|127\.0\.0\.1|0\.0\.0\.0|db|postgres|mysql|redis|mongo|host\.docker\.internal)$/i.test(host);
}

export const REDACTED = '[REDACTED]';

/// The text with every credential replaced, and where each one was.
export function redact(path: string, text: string): { text: string; findings: SecretFinding[] } {
  const findings: SecretFinding[] = [];
  const lineOf = (index: number) => text.slice(0, index).split('\n').length;
  const spans: [number, number, string][] = [];
  for (const [kind, re] of PATTERNS) {
    re.lastIndex = 0;
    for (const m of text.matchAll(re)) {
      if (kind === 'Connection string with password' && placeholderConnection(m[0])) continue;
      spans.push([m.index!, m.index! + m[0].length, kind]);
    }
  }
  GENERIC.lastIndex = 0;
  // Fixtures in tests are made-up values; only the providers' own formats
  // (above) are looked for there.
  const isTest = /(^|\/)(tests?|__tests__|spec|fixtures?|e2e)\/|[._-](test|spec)\.|_test\.\w+$/.test(path);
  for (const m of isTest ? [] : text.matchAll(GENERIC)) {
    const value = m[3];
    if (PLACEHOLDER.test(value)) continue;
    const start = m.index! + m[0].lastIndexOf(value);
    spans.push([start, start + value.length, 'Hard-coded secret']);
  }
  if (spans.length === 0) return { text, findings };
  spans.sort((a, b) => a[0] - b[0]);
  let out = '';
  let at = 0;
  for (const [s, e, kind] of spans) {
    if (s < at) continue; // overlapping matches: the first wins
    out += text.slice(at, s) + REDACTED;
    // A Firebase web config's apiKey identifies the project and is meant to
    // ship inside the app; it is noted, not raised as a leak.
    const firebaseWeb = kind === 'Google API key' && /firebase|apiKey\s*:/i.test(text.slice(Math.max(0, s - 300), s));
    findings.push({ path, line: lineOf(s), kind: firebaseWeb ? 'Firebase web API key' : kind, severity: firebaseWeb ? 'info' : 'high' });
    at = e;
  }
  out += text.slice(at);
  return { text: out, findings };
}

/// The names in a committed `.env.example`, without their values.
export function envNames(text: string): string[] {
  const names: string[] = [];
  for (const line of text.split('\n')) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(line);
    if (m) names.push(m[1]);
  }
  return names;
}
