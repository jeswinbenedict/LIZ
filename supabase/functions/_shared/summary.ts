// One definition of "summarise a tool", shared by the on-demand /summarize
// endpoint and the summarize-tools backfill.
//
// The response shape matters more than it looks: asking for a bare JSON array
// produced output the parser could not read, and the backfill silently wrote
// nothing. Asking for {"bullets": [...]} is what actually round-trips, so both
// callers use this rather than each spelling out a prompt.

import { completeText, extractJson } from './ai.ts';

export const SUMMARY_SYSTEM =
  'You write crisp, factual 3-bullet summaries of AI tools and tech news for a ' +
  'discovery app. Each bullet is one short sentence, benefit-focused, no hype. ' +
  'Respond ONLY with JSON: {"bullets": ["...","...","..."]}.';

/// Pulls the bullets out of a model reply, tolerating prose or code fences
/// around the JSON and dropping anything that isn't a usable line.
export function parseBullets(text: string): string[] {
  const parsed = extractJson<{ bullets?: unknown }>(text, {});
  const raw = Array.isArray(parsed?.bullets)
    ? parsed.bullets
    // Some replies come back as a bare array despite the instruction.
    : Array.isArray(parsed)
    ? parsed
    : [];

  return raw
    .filter((b): b is string => typeof b === 'string' && b.trim().length > 0)
    .map((b) => b.trim())
    .slice(0, 3);
}

export async function summarize(
  { title, description, kind = 'tool' }: {
    title?: string;
    description?: string;
    kind?: string;
  },
): Promise<string[]> {
  const text = await completeText({
    system: SUMMARY_SYSTEM,
    // Room for a reasoning model to think briefly and still answer.
    maxTokens: 1000,
    user: `Kind: ${kind}\nTitle: ${title ?? ''}\nDescription: ${description ?? ''}`,
  });
  return parseBullets(text);
}
