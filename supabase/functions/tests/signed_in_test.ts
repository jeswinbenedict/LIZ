import { assertEquals } from 'jsr:@std/assert@1';
import { signedInUid } from '../_shared/signed_in.ts';

// ask-liz reads the catalog with the service role, so it checks the caller
// itself: the platform's JWT check would pass the anon key every visitor holds.

const req = (auth?: string) =>
  new Request('https://x.test/ask-liz', {
    headers: auth ? { Authorization: auth } : {},
  });

const verify = (token: string, projectId: string) =>
  Promise.resolve(
    token === 'good' && projectId === 'liz-f5f93'
      ? { sub: 'fb-user-1', iss: '', aud: '', exp: 0, iat: 0 }
      : null,
  );

Deno.test('a verified Firebase token is a signed-in caller', async () => {
  assertEquals(
    await signedInUid(req('Bearer good'), { verify, projectId: 'liz-f5f93' }),
    'fb-user-1',
  );
});

Deno.test('no token, the anon key or a bad token is nobody', async () => {
  for (const auth of [undefined, 'Bearer anon.key.jwt', 'Bearer bad', 'good']) {
    assertEquals(
      await signedInUid(req(auth), { verify, projectId: 'liz-f5f93' }),
      null,
      String(auth),
    );
  }
});

Deno.test('without a Firebase project nobody is signed in', async () => {
  assertEquals(await signedInUid(req('Bearer good'), { verify, projectId: '' }), null);
});
