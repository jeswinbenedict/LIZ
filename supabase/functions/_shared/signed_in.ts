// Who is asking, for functions that serve only signed-in people.
//
// Since 5 October 2026 Liz is for signed-in people, the catalog included
// (migration 0061). A function that reads the catalog with the service role —
// ask-liz — must check the caller itself: the platform's own JWT check would
// pass the public anon key, which every visitor holds.

import { bearerToken } from './auth.ts';
import { type FirebaseClaims, verifyFirebaseToken } from './firebase.ts';
import { serviceAccount } from './google.ts';

type Verify = (token: string, projectId: string) => Promise<FirebaseClaims | null>;

/// The Firebase uid of a signed-in caller, or null for anyone else — no token,
/// the anon key, an expired or forged token, or one for another project.
export async function signedInUid(
  req: Request,
  options: { verify?: Verify; projectId?: string } = {},
): Promise<string | null> {
  const token = bearerToken(req);
  if (!token) return null;
  const projectId = options.projectId ?? serviceAccount()?.project_id;
  if (!projectId) return null;
  const claims = await (options.verify ?? verifyFirebaseToken)(token, projectId);
  return claims?.sub ?? null;
}
