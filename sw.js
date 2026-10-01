const CACHE_NAME = 'school-ms-cache-v3';
const APP_SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];
const SHELL_TIMEOUT_MS = 4000;
const PRECACHE_LIBS = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.js',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.all([
        ...APP_SHELL.map((url) =>
          fetch(url, { cache: 'reload' }).then((response) => {
            if (response && response.ok) return cache.put(url, response);
          }).catch(() => {})
        ),
        ...PRECACHE_LIBS.map((url) =>
          cache.match(url).then((hit) => {
            if (hit) return;
            return fetch(url).then((response) => {
              if (response && response.ok) return cache.put(url, response);
            });
          }).catch(() => {})
        )
      ])
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = e.request.url;

  // Google Fonts: stale-while-revalidate
  if (e.request.method === 'GET' &&
      (url.startsWith('https://fonts.googleapis.com/') || url.startsWith('https://fonts.gstatic.com/'))) {
    e.respondWith(
      caches.open(CACHE_NAME).then((cache) =>
        cache.match(e.request).then((cached) => {
          const net = fetch(e.request).then((response) => {
            if (response && (response.ok || response.type === 'opaque')) {
              cache.put(e.request, response.clone());
            }
            return response;
          }).catch(() => cached || Response.error());
          return cached || net;
        })
      )
    );
    return;
  }

  const isData = url.includes('jsdelivr.net');

  if (isData) {
    // Libraries / data: cache-first — once saved, never fetched again
    e.respondWith(
      caches.open(CACHE_NAME).then((cache) =>
        cache.match(e.request).then((cached) => {
          if (cached) return cached;
          return fetch(e.request).then((response) => {
            if (response && response.ok) cache.put(e.request, response.clone());
            return response;
          });
        })
      )
    );
    return;
  }

  // Only manage this app's own same-origin GET requests (the shell).
  // Every Supabase call is cross-origin and is left completely alone.
  let sameOriginGet = false;
  try {
    sameOriginGet = e.request.method === 'GET' && new URL(url).origin === self.location.origin;
  } catch (err) { /* not ours, pass through */ }

  if (!sameOriginGet) return;

  // Shell: network-first, but fall back to cache after SHELL_TIMEOUT_MS.
  const network = fetch(e.request, { cache: 'no-store' }).then((response) => {
    if (response && response.ok) {
      const copy = response.clone();
      caches.open(CACHE_NAME).then((cache) => cache.put(e.request, copy));
    }
    return response;
  });
  e.waitUntil(network.catch(() => {})); // let the update finish in background

  e.respondWith(
    caches.match(e.request).then((cached) => {
      if (!cached) return network;
      const timeout = new Promise((resolve) => setTimeout(() => resolve(null), SHELL_TIMEOUT_MS));
      return Promise.race([network.catch(() => null), timeout]).then((r) => r || cached);
    })
  );
});

// Shows the actual OS notification when a push arrives from
// send-checkin-reminders. The payload is the JSON string built in that
// Edge Function: { title, body }.
self.addEventListener('push', (e) => {
  let data = { title: 'Reminder', body: '' };
  try { data = e.data ? e.data.json() : data; } catch (err) { /* non-JSON payload, keep default */ }
  e.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: './icon-192.png',
      badge: './icon-192.png',
    })
  );
});

// Tapping the notification focuses an already-open tab if there is one,
// otherwise opens the app.
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientsArr) => {
      const existing = clientsArr.find((c) => 'focus' in c);
      if (existing) return existing.focus();
      return self.clients.openWindow('./');
    })
  );
});
