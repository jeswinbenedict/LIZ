// Free, open-source AI provider client (OpenAI-compatible Chat Completions).
//
// Defaults to GROQ — free, fast, and it serves open-source models (Llama, etc.).
// Because the API shape is OpenAI-compatible, you can switch providers with only
// env vars — no code change:
//
//   Groq (default):
//     AI_BASE_URL = https://api.groq.com/openai/v1
//     AI_MODEL    = llama-3.3-70b-versatile
//     AI_API_KEY  = gsk_...            (free at console.groq.com)
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
const AI_MODEL = Deno.env.get('AI_MODEL') ?? 'llama-3.3-70b-versatile';

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

  const res = await fetch(`${AI_BASE_URL}/chat/completions`, {
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
