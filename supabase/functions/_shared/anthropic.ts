// Minimal Anthropic Messages API client for Deno Edge Functions.
//
// Raw HTTP is used deliberately here: Supabase Edge Functions run on Deno and
// this keeps the function bundle dependency-free. Never mix this with the
// official SDK in the same file.
//
// Model defaults to claude-opus-5 (the current, most capable Opus). Override
// with the ANTHROPIC_MODEL env var if you want a cheaper model for high-volume
// ingest summarization (e.g. claude-haiku-4-5).

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const MODEL = Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-opus-5';

export interface AskResult {
  text: string;
}

/// Calls the Messages API and returns the concatenated text of the response.
export async function completeText({
  system,
  user,
  maxTokens = 1024,
}: {
  system?: string;
  user: string;
  maxTokens?: number;
}): Promise<string> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error('ANTHROPIC_API_KEY is not configured.');
  }

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: maxTokens,
      ...(system ? { system } : {}),
      messages: [{ role: 'user', content: user }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Anthropic API error ${res.status}: ${body}`);
  }

  const data = await res.json();
  // Guard for the refusal stop reason before reading content (Opus 5 can decline).
  if (data.stop_reason === 'refusal') {
    return '';
  }
  const blocks: Array<{ type: string; text?: string }> = data.content ?? [];
  return blocks
    .filter((b) => b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join('\n')
    .trim();
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
