// The loops embed-tools and summarize-tools run over a batch of tools, with
// the model and the database passed in, so the rules about what counts as a
// failure can be tested without either.

/** The batch size a caller asked for, within [1, max]. */
export function clampLimit(body: unknown, fallback: number, max: number): number {
  const asked = Number((body as { limit?: unknown } | null)?.limit);
  if (!Number.isFinite(asked) || asked < 1) return fallback;
  return Math.min(Math.floor(asked), max);
}

export interface SummaryTool {
  id: string;
  name: string;
  tagline?: string | null;
  description?: string | null;
}

export interface SummaryDeps {
  summarize: (input: { title: string; description: string }) => Promise<string[]>;
  /** Saves the bullets; resolves to an error message or null. */
  save: (id: string, bullets: string[]) => Promise<string | null>;
  /** Records that a row produced nothing usable (0026). */
  noteAttempt: (id: string) => Promise<void>;
}

/**
 * Summarises each tool, keeping count of what worked.
 *
 * Only an empty result is held against the row. A row that yields nothing
 * usable will usually yield nothing again, and after three such attempts it
 * leaves the backlog. A thrown error is a rate limit or a network failure,
 * which is not the row's fault, so it is not counted.
 */
export async function summarizeBatch(tools: SummaryTool[], deps: SummaryDeps) {
  let summarized = 0;
  const failures: string[] = [];
  for (const tool of tools) {
    try {
      const bullets = await deps.summarize({
        title: tool.name,
        description: `${tool.tagline ?? ''} ${tool.description ?? ''}`.trim(),
      });
      if (bullets.length === 0) {
        failures.push(`${tool.name}: no usable bullets`);
        await deps.noteAttempt(tool.id);
        continue;
      }
      const error = await deps.save(tool.id, bullets);
      if (error) failures.push(`${tool.name}: ${error}`);
      else summarized++;
    } catch (err) {
      failures.push(`${tool.name}: ${String(err)}`);
    }
  }
  return { summarized, failures };
}

export interface EmbedDeps<T> {
  text: (tool: T) => string;
  embed: (text: string) => Promise<number[]>;
  /** Saves the vector; resolves to an error message or null. */
  save: (id: string, vector: number[]) => Promise<string | null>;
}

/** Embeds each tool that has text to embed, keeping count of what worked. */
export async function embedBatch<T extends { id: string }>(
  tools: T[],
  deps: EmbedDeps<T>,
) {
  let embedded = 0;
  const failures: string[] = [];
  for (const tool of tools) {
    const text = deps.text(tool);
    if (!text) continue;
    try {
      const error = await deps.save(tool.id, await deps.embed(text));
      if (error) failures.push(`${tool.id}: ${error}`);
      else embedded++;
    } catch (err) {
      failures.push(`${tool.id}: ${String(err)}`);
    }
  }
  return { embedded, failures };
}
