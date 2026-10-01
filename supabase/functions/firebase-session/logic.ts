// What firebase-session decides, with its three outside calls passed in so
// every branch can be tested without Firebase or a database.

import type { FirebaseClaims } from '../_shared/firebase.ts';

export interface SessionDeps {
  /** The verified claims of the caller's Firebase ID token, or null. */
  claims: () => Promise<FirebaseClaims | null>;
  /** link_firebase_account(): the Liz user id, or null to verify first. */
  link: (args: {
    firebaseUid: string;
    email: string | null;
    emailVerified: boolean;
    displayName: string | null;
    avatarUrl: string | null;
  }) => Promise<string | null>;
  /** Replaces the Firebase account's custom claims. */
  setClaims: (uid: string, claims: Record<string, unknown>) => Promise<void>;
}

export interface SessionBody {
  display_name?: unknown;
}

export interface SessionOutcome {
  status: number;
  body: {
    data:
      | { user_id: string; refresh: boolean }
      | { needs_verification: true }
      | null;
    error: string | null;
  };
}

/**
 * Turns a Firebase sign-in into a Liz session.
 *
 * Finds or creates the Liz user the account signs in as, then makes sure the
 * account's tokens carry what Supabase needs: `role: authenticated` (without
 * it every request runs as a guest) and `liz_uid`, so current_uid() needs no
 * lookup. When the claims change the client must refresh its token, and
 * `refresh` says so.
 */
export async function startSession(deps: SessionDeps, body: SessionBody): Promise<SessionOutcome> {
  const claims = await deps.claims();
  if (!claims) return { status: 401, body: { data: null, error: 'Sign in required' } };

  const typed = typeof body.display_name === 'string' ? body.display_name.trim().slice(0, 60) : '';
  const userId = await deps.link({
    firebaseUid: claims.sub,
    email: typeof claims.email === 'string' ? claims.email : null,
    emailVerified: claims.email_verified === true,
    displayName: typed || (typeof claims.name === 'string' ? claims.name : null),
    avatarUrl: typeof claims.picture === 'string' ? claims.picture : null,
  });
  if (!userId) {
    return { status: 200, body: { data: { needs_verification: true }, error: null } };
  }

  const current = claims.role === 'authenticated' && claims.liz_uid === userId;
  if (!current) {
    await deps.setClaims(claims.sub, { role: 'authenticated', liz_uid: userId });
  }
  return { status: 200, body: { data: { user_id: userId, refresh: !current }, error: null } };
}
