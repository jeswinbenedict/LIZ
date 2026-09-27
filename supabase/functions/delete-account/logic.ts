// The decision delete-account makes, with the two calls it depends on passed
// in, so every branch can be tested without an auth server.

export interface DeleteDeps {
  /** The id of the user the request's own session belongs to, or null. */
  callerId: () => Promise<string | null>;
  /** Deletes that auth user; resolves to an error message or null. */
  deleteUser: (id: string) => Promise<string | null>;
}

export interface Outcome {
  status: number;
  body: { data: { ok: true } | null; error: string | null };
}

/**
 * Deletes the caller's own account, and nobody else's.
 *
 * The id comes only from the caller's session, never from the request body,
 * so there is no parameter anyone could set to someone else's id.
 */
export async function deleteCaller(deps: DeleteDeps): Promise<Outcome> {
  const id = await deps.callerId();
  if (!id) return { status: 401, body: { data: null, error: 'Sign in required' } };

  const error = await deps.deleteUser(id);
  if (error) return { status: 400, body: { data: null, error } };

  return { status: 200, body: { data: { ok: true }, error: null } };
}
