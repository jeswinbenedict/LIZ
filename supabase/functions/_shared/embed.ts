// Embeddings via `gte-small`, which ships inside the Supabase Edge Runtime.
//
// Open source, runs in-process, needs no API key and costs nothing per call —
// unlike a hosted embeddings API. 384 dimensions, matching the vector(384)
// column in migration 0014.
//
// Tools and queries must be embedded by this same helper: vectors from
// different models are not comparable, and mixing them silently returns
// nonsense rankings rather than an error.

// Provided by the Edge Runtime; not part of the Deno namespace.
declare const Supabase: {
  ai: {
    Session: new (model: string) => {
      run(
        input: string,
        opts?: { mean_pool?: boolean; normalize?: boolean },
      ): Promise<number[]>;
    };
  };
};

export const EMBEDDING_MODEL = 'gte-small';
export const EMBEDDING_DIMS = 384;

// gte-small truncates around 512 tokens; trim first so the tail of a long
// description cannot push the tagline out of the window.
const MAX_CHARS = 1500;

let session: ReturnType<typeof createSession> | null = null;

function createSession() {
  return new Supabase.ai.Session(EMBEDDING_MODEL);
}

export async function embed(text: string): Promise<number[]> {
  const input = text.trim().slice(0, MAX_CHARS);
  if (!input) throw new Error('embed() called with empty text');
  session ??= createSession();
  // mean_pool + normalize give unit vectors, which is what cosine distance
  // in match_tools expects.
  return await session.run(input, { mean_pool: true, normalize: true });
}

export type EmbeddableTool = {
  name?: string | null;
  tagline?: string | null;
  description?: string | null;
  category?: string | null;
  tags?: string[] | null;
};

/// Builds the text that represents a tool in vector space.
///
/// Leads with what the tool *does* rather than its name: a user asking to
/// "remove image backgrounds" describes a job, not a brand, so the functional
/// wording is what needs to dominate the embedding.
export function toolText(t: EmbeddableTool): string {
  const parts = [
    t.tagline ?? '',
    t.description ?? '',
    (t.tags ?? []).join(', '),
    (t.category ?? '').replace(/^ai-/, ''),
    t.name ?? '',
  ];
  return parts.map((p) => p.trim()).filter(Boolean).join('. ');
}
