// A budget for the functions that have to stay anonymous.
//
// `ask-liz` runs an embedding model per call and `logo` fetches an upstream
// image per call, so neither can be both public and unlimited. Neither should
// be behind a login either — a visitor asks a question or loads a page of
// logos without an account, and that is the product working.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/// Who to charge a request to.
///
/// Supabase puts the caller's address in x-forwarded-for; the first entry is
/// the client and the rest are proxies. It is spoofable by anyone willing to
/// set a header, so this is a cost ceiling rather than an access control — it
/// stops a script left running, not a determined attacker. The real protection
/// against those is that these two functions cannot write anything.
export function callerKey(req: Request, prefix: string): string {
  const forwarded = req.headers.get('x-forwarded-for') ?? '';
  const address = forwarded.split(',')[0].trim();
  return `${prefix}:${address || 'unknown'}`;
}

let cached: SupabaseClient | null = null;

function admin(): SupabaseClient | null {
  if (cached) return cached;
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  cached = createClient(url, key);
  return cached;
}

/// Counts this request and says whether it is within budget.
///
/// Fails **open**. A rate limiter that takes the feature down when the
/// database hiccups has caused a worse outage than the abuse it was guarding
/// against, and the thing being protected here is a bill, not data.
export async function withinRateLimit(
  key: string,
  maxHits: number,
  windowLength = '1 hour',
): Promise<boolean> {
  const client = admin();
  if (!client) return true;
  try {
    const { data, error } = await client.rpc('take_rate_limit', {
      bucket_key: key,
      max_hits: maxHits,
      window_length: windowLength,
    });
    if (error) return true;
    return data !== false;
  } catch (_) {
    return true;
  }
}

/// A limiter that needs no round trip, for hot paths where one would be felt.
///
/// Edge functions are ephemeral and run as several instances, so this counts
/// only what one instance saw and is a blunt instrument by design. It is here
/// because a page of the catalog fires dozens of logo requests, and adding a
/// database call to each one to save a favicon fetch would be a poor trade.
export class InMemoryLimiter {
  private hits = new Map<string, { count: number; resetAt: number }>();

  constructor(
    private readonly maxHits: number,
    private readonly windowMs: number,
  ) {}

  take(key: string): boolean {
    const now = Date.now();
    const entry = this.hits.get(key);

    if (!entry || now >= entry.resetAt) {
      this.hits.set(key, { count: 1, resetAt: now + this.windowMs });
      // Opportunistic sweep: without it a long-lived instance accumulates a
      // key per address it has ever seen.
      if (this.hits.size > 5000) {
        for (const [k, v] of this.hits) {
          if (now >= v.resetAt) this.hits.delete(k);
        }
      }
      return true;
    }

    entry.count += 1;
    return entry.count <= this.maxHits;
  }
}

/// The response a caller over budget gets.
export function tooManyRequests(retryAfterSeconds: number): Response {
  return new Response(
    JSON.stringify({ data: null, error: 'Too many requests' }),
    {
      status: 429,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
        // Say when to come back rather than leaving a client to guess and
        // retry in a tight loop.
        'Retry-After': String(retryAfterSeconds),
      },
    },
  );
}
