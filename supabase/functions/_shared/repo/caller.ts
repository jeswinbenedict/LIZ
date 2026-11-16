// Who is asking, as a Liz user id, for the Repository Analyzer's functions.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { signedInUid } from '../signed_in.ts';
import { GitHubError } from './github.ts';
import { json } from '../cors.ts';

export function admin(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    // service role: server-side only, never exposed to the client
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}

/// The caller's Liz user id (profiles.id), or null when not signed in.
export async function lizUid(req: Request, db: SupabaseClient): Promise<string | null> {
  const firebase = await signedInUid(req);
  if (!firebase) return null;
  const { data } = await db.from('firebase_accounts').select('user_id').eq('firebase_uid', firebase).maybeSingle();
  return (data?.user_id as string | undefined) ?? null;
}

/// A personal access token as GitHub issues them, or null; never logged.
export function cleanToken(token: unknown): string | null | undefined {
  if (token == null || token === '') return null;
  if (typeof token !== 'string' || token.length > 255 || !/^[A-Za-z0-9_]+$/.test(token.trim())) return undefined;
  return token.trim();
}

/// A GitHub failure as an answer the app can show.
export function githubFailure(e: GitHubError): Response {
  const status = { not_found: 404, bad_token: 401, forbidden: 403, rate_limited: 429, too_large: 413 }[e.code] ?? 502;
  return json({ data: null, error: e.message, code: e.code, resetAt: e.resetAt ?? null }, status);
}
