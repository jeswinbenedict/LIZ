// Free, open-source AI provider client (OpenAI-compatible Chat Completions).
//
// Defaults to GROQ — free, fast, and it serves open-source models.
// Because the API shape is OpenAI-compatible, you can switch providers with only
// env vars — no code change:
//
//   Groq (default):
//     AI_BASE_URL = https://api.groq.com/openai/v1
//     AI_MODEL    = openai/gpt-oss-20b
//     AI_API_KEY  = gsk_...            (free at console.groq.com)
//
// Model IDs expire. `llama-3.3-70b-versatile` was the default until Groq moved
// it behind an enterprise plan, and every call started failing with a 404
// ("does not exist or you do not have access to it") — summaries silently
// stopped being written for months. If summarize starts 404ing, check
// console.groq.com/docs/models for the current production list rather than
// assuming the key is at fault.
//
//   OpenRouter (free models):
//     AI_BASE_URL = https://openrouter.ai/api/v1
//     AI_MODEL    = meta-llama/llama-3.3-70b-instruct:free
//     AI_API_KEY  = sk-or-...          (free at openrouter.ai)
//
//   Google Gemini (OpenAI-compat endpoint):
//     AI_BASE_URL = https://generativelanguage.googleapis.com/v1beta/openai
//     AI_MODEL    = gemini-2.0-flash
//     AI_API_KEY  = AIza...            (free at aistudio.google.com)
//
// A second provider, optional, is tried when the first is down, out of quota
// or has retired its model — the failure that once stopped summaries for
// months. Same three settings with a FALLBACK prefix, for example OpenRouter:
//     AI_FALLBACK_BASE_URL = https://openrouter.ai/api/v1
//     AI_FALLBACK_MODEL    = meta-llama/llama-3.3-70b-instruct:free
//     AI_FALLBACK_API_KEY  = sk-or-...
// A reply that is merely unhelpful is not retried elsewhere: only a provider
// that fails to answer.
//
// Keys expire. In November 2026 the Groq key began answering 401
// "expired_api_key" and every summary failed; the scrape run retried the same
// three tools twelve times a day before failing. A key every provider refuses
// now raises AiCredentialsError, which callers treat as "stop and say so".

/// Every configured provider refused its key (401 or 403). Nothing later in a
/// batch can succeed until the key is renewed, so callers stop at once.
export class AiCredentialsError extends Error {}

/// One provider refusing its key, as opposed to being down or rate limited.
class KeyRefused extends Error {}

export interface Provider {
  name: string;
  baseUrl: string;
  model: string;
  apiKey: string;
}

/// The primary provider and, when all three of its settings are present, the
/// fallback. Read through [env] so tests can supply their own.
export function providersFrom(env: (key: string) => string | undefined): Provider[] {
  const primary: Provider = {
    name: 'primary',
    baseUrl: (env('AI_BASE_URL') ?? 'https://api.groq.com/openai/v1').replace(/\/$/, ''),
    model: env('AI_MODEL') ?? 'openai/gpt-oss-20b',
    apiKey: env('AI_API_KEY') ?? '',
  };
  const fb = {
    baseUrl: env('AI_FALLBACK_BASE_URL') ?? '',
    model: env('AI_FALLBACK_MODEL') ?? '',
    apiKey: env('AI_FALLBACK_API_KEY') ?? '',
  };
  const providers = primary.apiKey ? [primary] : [];
  if (fb.baseUrl && fb.model && fb.apiKey) {
    providers.push({ name: 'fallback', ...fb, baseUrl: fb.baseUrl.replace(/\/$/, '') });
  }
  return providers;
}

const MAX_RATE_LIMIT_RETRIES = 3;
const DEFAULT_RETRY_MS = 4000;
const MAX_RETRY_MS = 20000;

/// How long to wait after a 429. `Retry-After` is seconds, or an HTTP date;
/// anything unparseable falls back to a fixed pause, capped so a function never
/// sits past its own wall-clock limit.
export function retryAfterMs(header: string | null): number {
  if (!header) return DEFAULT_RETRY_MS;
  const seconds = Number(header);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(seconds * 1000, MAX_RETRY_MS);
  }
  const at = Date.parse(header);
  if (!Number.isNaN(at)) {
    return Math.min(Math.max(at - Date.now(), 0), MAX_RETRY_MS);
  }
  return DEFAULT_RETRY_MS;
}

export interface CompleteOptions {
  system?: string;
  user: string;
  maxTokens?: number;
}

type Fetch = typeof fetch;
type Sleep = (ms: number) => Promise<void>;
const sleep: Sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// One provider's answer, or a thrown error saying why there was none.
async function askOne(
  p: Provider,
  { system, user, maxTokens = 1024 }: CompleteOptions,
  fetchFn: Fetch,
  wait: Sleep,
): Promise<string> {
  const request = () =>
    fetchFn(`${p.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${p.apiKey}`,
        'Content-Type': 'application/json',
        // OpenRouter likes these; harmless elsewhere.
        'HTTP-Referer': 'https://liz-cfp.pages.dev',
        'X-Title': 'Liz',
      },
      body: JSON.stringify({
        model: p.model,
        messages: [
          ...(system ? [{ role: 'system', content: system }] : []),
          { role: 'user', content: user },
        ],
        max_tokens: maxTokens,
        temperature: 0.4,
        // gpt-oss is a reasoning model: it spends tokens thinking before it
        // answers, and on a harder input (Chinese text, a paper title, URLs)
        // the thinking could use up the whole budget and leave no answer.
        // Summaries and rankings need little of it. Only sent to the models
        // that accept it; other providers reject unknown parameters.
        ...(p.model.startsWith('openai/gpt-oss') ? { reasoning_effort: 'low' } : {}),
      }),
    });

  // Free tiers cap requests per minute, and a batch job walks straight into it.
  // Wait the interval the provider asks for rather than discarding the row:
  // an unattended run has nobody to notice and retry it.
  let res = await request();
  for (let attempt = 0; attempt < MAX_RATE_LIMIT_RETRIES && res.status === 429; attempt++) {
    await wait(retryAfterMs(res.headers.get('retry-after')));
    res = await request();
  }

  if (!res.ok) {
    const body = await res.text();
    const message = `AI API error ${res.status} (${p.name}): ${body.slice(0, 300)}`;
    throw res.status === 401 || res.status === 403 ? new KeyRefused(message) : new Error(message);
  }

  const data = await res.json();
  const choice = data?.choices?.[0];
  const content: string = (choice?.message?.content ?? '').trim();
  // Out of tokens before any answer is the budget's fault, not the input's.
  // Thrown rather than returned empty, so a caller that counts empty answers
  // against a row (summarize-tools, after three) does not write it off.
  if (!content && choice?.finish_reason === 'length') {
    throw new Error(`the model ran out of tokens before answering (${p.name})`);
  }
  return content;
}

/// Asks each provider in turn until one answers. Split from [completeText]
/// so tests can pass providers, a fake fetch and an instant sleep.
export async function completeWith(
  providers: Provider[],
  options: CompleteOptions,
  fetchFn: Fetch = fetch,
  wait: Sleep = sleep,
): Promise<string> {
  if (providers.length === 0) {
    throw new Error('AI_API_KEY is not configured (set a free Groq/OpenRouter/Gemini key).');
  }
  const errors: string[] = [];
  let refused = 0;
  for (const p of providers) {
    try {
      return await askOne(p, options, fetchFn, wait);
    } catch (e) {
      if (e instanceof KeyRefused) refused++;
      errors.push(e instanceof Error ? e.message : String(e));
      if (providers.length > 1) console.warn(`AI provider ${p.name} failed: ${errors.at(-1)}`);
    }
  }
  const message = errors.join(' | ');
  throw refused === providers.length ? new AiCredentialsError(message) : new Error(message);
}

const PROVIDERS = providersFrom((k) => Deno.env.get(k));

/// Calls the configured provider (then the fallback, if one is set) and
/// returns the text reply.
export function completeText(options: CompleteOptions): Promise<string> {
  return completeWith(PROVIDERS, options);
}

/// Extracts a JSON value from a model response that may be wrapped in prose or
/// ```json fences.
export function extractJson<T>(text: string, fallback: T): T {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.search(/[[{]/);
  if (start === -1) return fallback;
  // The JSON may be followed by a sentence of prose. Try the longest span that
  // ends on a closing bracket first, then shorter ones.
  const body = candidate.slice(start);
  for (let end = body.length; end > 0; end--) {
    const c = body[end - 1];
    if (c !== '}' && c !== ']') continue;
    try {
      return JSON.parse(body.slice(0, end)) as T;
    } catch (_) {
      // Keep looking for an earlier closing bracket.
    }
  }
  return fallback;
}
