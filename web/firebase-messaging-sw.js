/* Liz — Firebase Cloud Messaging service worker (web push).
 *
 * TEMPLATE: replace the config below with your Firebase *web app* config
 * (Firebase console → Project settings → General → Your apps → Web → SDK config).
 * This file is served at /firebase-messaging-sw.js and handles background web
 * notifications. It is inert until you fill in a real config AND build the app
 * with --dart-define=FCM_VAPID_KEY=<web-push-cert-key>.
 *
 * The compat SDK is loaded from Google's CDN (allowed for the service worker).
 */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA9X8p7Bpg7DwRTRDUIz6VOjFKYvpUBB6w',
  authDomain: 'lizzy-50dc0.firebaseapp.com',
  projectId: 'lizzy-50dc0',
  messagingSenderId: '828408834851',
  appId: '1:828408834851:web:4a36206ab71ff2af3e3a96',
});

const messaging = firebase.messaging();

// Show background notifications and route on click.
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || 'Liz', {
    body: n.body || '',
    icon: '/icons/Icon-192.png',
    data: { route: (payload.data && payload.data.route) || '/' },
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = (event.notification.data && event.notification.data.route) || '/';
  event.waitUntil(clients.openWindow(route));
});
