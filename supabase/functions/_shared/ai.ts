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

const AI_API_KEY = Deno.env.get('AI_API_KEY') ?? '';
const AI_BASE_URL =
  (Deno.env.get('AI_BASE_URL') ?? 'https://api.groq.com/openai/v1').replace(/\/$/, '');
const AI_MODEL = Deno.env.get('AI_MODEL') ?? 'openai/gpt-oss-20b';

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

/// Calls the provider's Chat Completions endpoint and returns the text reply.
export async function completeText({
  system,
  user,
  maxTokens = 1024,
}: {
  system?: string;
  user: string;
  maxTokens?: number;
}): Promise<string> {
  if (!AI_API_KEY) {
    throw new Error('AI_API_KEY is not configured (set a free Groq/OpenRouter/Gemini key).');
  }

  const request = () =>
    fetch(`${AI_BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${AI_API_KEY}`,
        'Content-Type': 'application/json',
        // OpenRouter likes these; harmless elsewhere.
        'HTTP-Referer': 'https://liz.app',
        'X-Title': 'Liz',
      },
      body: JSON.stringify({
        model: AI_MODEL,
        messages: [
          ...(system ? [{ role: 'system', content: system }] : []),
          { role: 'user', content: user },
        ],
        max_tokens: maxTokens,
        temperature: 0.4,
      }),
    });

  // Free tiers cap requests per minute, and a batch job walks straight into it.
  // Wait the interval the provider asks for rather than discarding the row:
  // an unattended run has nobody to notice and retry it.
  let res = await request();
  for (let attempt = 0; attempt < MAX_RATE_LIMIT_RETRIES && res.status === 429; attempt++) {
    const wait = retryAfterMs(res.headers.get('retry-after'));
    await new Promise((resolve) => setTimeout(resolve, wait));
    res = await request();
  }

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`AI API error ${res.status}: ${body}`);
  }

  const data = await res.json();
  const content: string = data?.choices?.[0]?.message?.content ?? '';
  return content.trim();
}

/// Extracts a JSON value from a model response that may be wrapped in prose or
/// ```json fences.
export function extractJson<T>(text: string, fallback: T): T {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.search(/[[{]/);
  if (start === -1) return fallback;
  try {
    return JSON.parse(candidate.slice(start)) as T;
  } catch (_) {
    return fallback;
  }
}
