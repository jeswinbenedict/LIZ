# Signing in: Firebase Authentication in front of Supabase

Decided 1 October 2026. Firebase handles who someone is; Supabase keeps
everything about them. Nothing moved to Firestore: ranking, search, Ask Liz,
the scheduled jobs and the access rules all depend on Postgres.

## How it fits together

```
 app ──sign in──▶ Firebase Auth ──ID token──▶ app
  │                                            │
  │   every Supabase request carries the token │ (Supabase.initialize accessToken)
  ▼                                            ▼
 firebase-session ──▶ link_firebase_account() ──▶ profiles / firebase_accounts
        │
        └─▶ Firebase: custom claims { role: "authenticated", liz_uid: <uuid> }
```

1. The app signs in with Firebase: email and password, Google, an email
   link, or — for moderators with an authenticator — password plus a code.
2. It calls the `firebase-session` Edge Function with the ID token. The
   function verifies the token itself, finds or creates the Liz user the
   account signs in as, and sets two custom claims on the Firebase account:
   - `role: authenticated` — without it Supabase treats every request as a
     guest's;
   - `liz_uid` — the Liz user id, so the database needs no lookup.
3. The app refreshes the token once (claims arrive in the next token) and
   loads the profile. From then on every request to Supabase carries the
   Firebase token, and Postgres reads it through `auth.jwt()`.

Liz user ids are still uuids. `current_uid()` (migration 0055) returns the
caller's: from `liz_uid`, from `firebase_accounts` in the moment before the
claim is set, or `auth.uid()` for a token Supabase issued itself. Every policy
and function uses it; `auth.uid()` would fail on a Firebase id, which is not a
uuid.

Firebase is started only when someone signs in, turns on notifications, or
returns to a browser that had a session — a first-time visitor downloads none
of it.

## The existing account

The one account from before the switch keeps its profile, saves and role. Its
owner signs up in Firebase with the same email address (or uses Google with
it). `link_firebase_account()` links it to the old profile once Firebase says
the address is verified; until then the app sends a confirmation email and
says so. Linking an unverified address would let anyone sign up with someone
else's email and walk into their account.

## One-time setup (owner)

In order. Nothing changes for visitors until the new build is deployed.

1. **Firebase console → Authentication → Get started** (project
   `liz-f5f93`). Under *Sign-in method* enable **Email/Password**, and in the
   same panel **Email link (passwordless sign-in)**. Enable **Google**.
2. **Authentication → Settings → Authorized domains**: add the domain Liz is
   deployed on (`localhost` is there already).
3. **Supabase dashboard → Authentication → Third-party Auth → Add provider →
   Firebase**, project ID `liz-f5f93`. Without this, Supabase rejects
   Firebase tokens and signed-in requests fail.
4. **Firebase service account**: the `FIREBASE_SERVICE_ACCOUNT` function
   secret (already set for push) must be the Admin SDK key of `liz-f5f93`
   (Firebase console → Project settings → Service accounts → Generate new
   private key). `firebase-session` uses it to set claims and
   `delete-account` to delete accounts.
5. **Optional — moderator two-step**: authenticator-app codes need Firebase
   Authentication with Identity Platform (Authentication → Settings → upgrade;
   free up to the Spark plan's limits) and TOTP switched on, which the
   console does not offer. With the service-account file:

   ```bash
   deno run --allow-read --allow-net tool/firebase_enable_totp.ts path/to/service-account.json
   ```

6. **Optional — Liz's own reset page**: Firebase hosts the page a reset email
   opens. To use Liz's instead, set Authentication → Templates → Password
   reset → *Customize action URL* to `https://<your domain>/reset-password`.
7. **Optional — Apple**: enable Apple in Firebase and build with
   `--dart-define=AUTH_PROVIDERS=google,apple`. The default is `google`.

## Emails

Firebase sends the confirmation, password-reset and sign-in-link emails from
its own servers, so Liz no longer needs an SMTP provider for sign-in. The
sender and wording are under Authentication → Templates.

## Server functions

| Function | Auth |
|---|---|
| `firebase-session` | Firebase ID token, verified in the function (`verify_jwt = false`) |
| `delete-account` | the same; deletes the profile (and with it everything tied to it), any pre-switch Supabase login, and the Firebase account |
| everything else | unchanged |

Tokens are verified against Google's published keys, the issuer and audience
for `liz-f5f93`, expiry, issue time and subject
(`supabase/functions/_shared/firebase.ts`, tested in
`tests/firebase_auth_test.ts`). On the hosted platform Supabase also rejects
tokens from Firebase projects other than the registered one before they reach
Postgres.
