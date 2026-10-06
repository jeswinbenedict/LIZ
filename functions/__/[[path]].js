// Firebase sign-in, served from Liz's own address.
//
// signInWithPopup opens Firebase's helper pages (/__/auth/handler, and a
// hidden /__/auth/iframe) on the project's authDomain. On the default,
// liz-f5f93.firebaseapp.com, they are a third party to the page, and a
// browser that blocks third-party storage — Brave's Shields, Safari's
// tracking prevention, Firefox's strict mode — breaks them: on 6 October 2026
// Brave reported "Sign-in isn't set up for this address yet" for a domain
// that was authorised. Relaying /__/auth/* and /__/firebase/* from this
// origin makes them first-party (Firebase's documented option: "proxy auth
// requests to firebaseapp.com"); the app sets authDomain to this host
// (lib/core/firebase/firebase_app.dart), and the Google OAuth client lists
// https://liz-cfp.pages.dev/__/auth/handler as a redirect URI.
//
// Only these two prefixes are relayed; anything else under /__/ is a 404.

const UPSTREAM = 'https://liz-f5f93.firebaseapp.com';

export async function onRequest({ request }) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/__/auth/') && !url.pathname.startsWith('/__/firebase/')) {
    return new Response('Not found', { status: 404 });
  }
  const upstream = new Request(UPSTREAM + url.pathname + url.search, request);
  const response = await fetch(upstream, { redirect: 'manual' });
  // Pass through untouched: the helper pages carry their own security
  // headers, and this site's CSP and frame rules (web/_headers) are not
  // meant for them.
  return response;
}
