# Liz — Push Notifications (FCM) Setup

Push is **code-complete and guarded**: the app builds and runs perfectly with or
without Firebase. In-app notifications (a reply to your post, a new follower)
already work the moment migration `0007_notifications.sql` is applied — **no
Firebase needed**. This checklist turns on **device push** on top of that.

Firebase Cloud Messaging is **free** for the web. Liz ships as a web
application only, so only the web setup below applies.

---

## What's already built

| Piece | Where | Status |
|---|---|---|
| Token capture + register | `lib/core/notifications/push_service.dart` → `devices` table | ✅ guarded, no-op without config |
| App wiring (init, re-register on sign-in, tap→route) | `lib/main.dart` | ✅ |
| In-app notifications (reply / follow / tool alerts / health) | `0007`, `0020`, `0024` migrations | ✅ works now |
| Push sender (FCM HTTP v1) | `supabase/functions/send-notification/index.ts` | ✅ deploy + set secret |
| Web background handler | `web/firebase-messaging-sw.js` | ⛏ fill config |

---

## 1. Create a free Firebase project
1. https://console.firebase.google.com → **Add project** (reuse your Google login).
2. Skip Google Analytics if you like.

## 2. Add the web app

1. Firebase console → **Add app → Web**. Copy the config object.
2. Paste it into **`web/firebase-messaging-sw.js`** (replace the `REPLACE_ME`s).
3. Also add it to `web/index.html` **only if** you want foreground web pushes —
   otherwise the service worker (background) is enough.
4. **Cloud Messaging → Web Push certificates → Generate key pair.** Copy the
   **VAPID key** — you pass it at build time (step 5).

## 3. Deploy the sender + set the Firebase secret
1. Firebase console → **Project settings → Service accounts → Generate new
   private key** → downloads a JSON file.
2. Set it as a Supabase secret (one line) and deploy:
   ```bash
   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat ~/Downloads/serviceAccount.json)"
   supabase functions deploy send-notification
   ```

## 4. Let the database fan out pushes
`notify_user()` reads two secrets from **Supabase Vault** (Supabase blocks
`ALTER DATABASE ... SET` for non-superusers, so Vault is the supported path).
In the dashboard → **SQL Editor**:
```sql
-- endpoint (not secret; may already be set)
select vault.create_secret(
  'https://<PROJECT_REF>.functions.supabase.co', 'functions_url', 'Push: sender URL');
-- the service_role bearer (Project Settings → API Keys → service_role → Reveal)
select vault.create_secret(
  '<SERVICE_ROLE_KEY>', 'service_role_key', 'Push: service role bearer');
```
Each returns a UUID on success. Rotate later with `vault.update_secret(id, '<new>')`
(find ids via `select id, name from vault.secrets;`). Until both exist, only
in-app notifications are written — by design.

## 5. Build the app with the web VAPID key
```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=FCM_VAPID_KEY=<web-push-cert-key>
```

---

## Test it
1. Run the app in a browser that allows notifications.
2. Sign in → accept the notification permission prompt. A row appears in
   `devices` with your `fcm_token`.
3. Have a second account **reply to your post** (or **follow you**).
4. You get a **push** (background) + an in-app `notifications` row.

Manual test of just the sender:
```bash
curl -X POST 'https://<PROJECT_REF>.functions.supabase.co/send-notification' \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"<your-user-uuid>","title":"Hello from Liz","body":"Push works 🎉","route":"/news"}'
```

## How it degrades (why it's safe)
- No `google-services.json` / web config → `Firebase.initializeApp()` throws →
  caught → push disabled, **app unaffected**.
- No `FIREBASE_SERVICE_ACCOUNT` secret → `send-notification` returns
  `{skipped:true}` (HTTP 200) → triggers never error.
- No `app.functions_url` DB setting → `notify_user()` writes the in-app row and
  skips the push call.

Every layer fails open to "in-app only," never to a crash.
