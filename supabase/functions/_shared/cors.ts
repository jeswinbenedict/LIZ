// Shared CORS headers for browser (Flutter web) access to Edge Functions.
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// A failed request, answered without its cause. Error messages and
/// stringified exceptions can carry stack traces, SQL, table and column
/// names; they go to the function's log, where operators read them, and the
/// caller gets a generic message. [where] names the function in the log.
export function failure(where: string, err: unknown, status = 500): Response {
  const detail = err instanceof Error ? (err.stack ?? err.message) : (err as { message?: string })?.message ?? String(err);
  console.error(`${where} failed:`, detail);
  return json({ data: null, error: status >= 500 ? 'Something went wrong. Try again in a minute.' : 'The request could not be completed.' }, status);
}
