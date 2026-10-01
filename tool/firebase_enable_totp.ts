// Switches on authenticator-app (TOTP) codes for Firebase Authentication,
// which moderator two-step needs and the Firebase console cannot do.
//
//   deno run --allow-read --allow-net tool/firebase_enable_totp.ts service-account.json
//
// The project must already be upgraded to Firebase Authentication with
// Identity Platform (console → Authentication → Settings). See docs/AUTH.md.

import { accessToken, type ServiceAccount } from '../supabase/functions/_shared/google.ts';

const path = Deno.args[0];
if (!path) {
  console.error('usage: firebase_enable_totp.ts <service-account.json>');
  Deno.exit(2);
}
const sa = JSON.parse(await Deno.readTextFile(path)) as ServiceAccount;
const token = await accessToken(sa, 'https://www.googleapis.com/auth/cloud-platform');

const res = await fetch(
  `https://identitytoolkit.googleapis.com/admin/v2/projects/${sa.project_id}/config?updateMask=mfa`,
  {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      mfa: {
        // Accept the code from one 30-second step either side, for a phone
        // clock that has drifted a little.
        providerConfigs: [{ state: 'ENABLED', totpProviderConfig: { adjacentIntervals: 1 } }],
      },
    }),
  },
);
const body = await res.text();
if (!res.ok) {
  console.error(`Failed (${res.status}): ${body}`);
  Deno.exit(1);
}
console.log(`TOTP two-step is on for ${sa.project_id}.`);
