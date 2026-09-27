// Pure parts of send-notification: who a request is for, what FCM is sent,
// and which failures mean a token is dead. Split out so they can be tested
// without Firebase.

/** The users a request names, from `user_ids` or a single `user_id`. */
export function targetIds(body: { user_id?: unknown; user_ids?: unknown }): string[] {
  if (Array.isArray(body.user_ids)) {
    return body.user_ids.filter((id): id is string => typeof id === 'string' && id !== '');
  }
  return typeof body.user_id === 'string' && body.user_id !== '' ? [body.user_id] : [];
}

/** One FCM v1 message for one device token. */
export function fcmMessage(
  token: string,
  push: { title: unknown; body?: unknown; route?: unknown; data?: Record<string, unknown> },
) {
  const route = push.route == null ? '' : String(push.route);
  return {
    message: {
      token,
      notification: { title: String(push.title), body: String(push.body ?? '') },
      // FCM data values must all be strings.
      data: Object.fromEntries(
        Object.entries({ route, ...(push.data ?? {}) }).map(([k, v]) => [k, String(v)]),
      ),
      // On the web, tapping the notification opens this link.
      webpush: route ? { fcm_options: { link: route } } : undefined,
    },
  };
}

/**
 * Whether an FCM failure means the token will never work again.
 *
 * 404 is UNREGISTERED — the browser dropped the subscription. 400 is an
 * invalid token. Anything else (429, 5xx) is FCM's problem, not the token's,
 * and pruning on it would sign people out of push over a bad minute.
 */
export function isDeadToken(status: number): boolean {
  return status === 404 || status === 400;
}
