const CACHE_NAME = 'school-ms-cache-v2';
const APP_SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
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
  const isData = url.includes('jsdelivr.net');

  if (isData) {
    // Data (Quran text + Tafsir): cache-first — once saved, never fetched again
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

  // Only manage this app's own same-origin GET requests (the shell: index.html,
  // manifest, icons). Everything else — and in particular every Supabase call,
  // which is cross-origin and mostly POST/PATCH/RPC — is left completely alone.
  //
  // Previously this branch caught ALL requests regardless of method or origin:
  // it tried cache.put() on every Supabase response too, which throws for
  // non-GET requests (the Cache API only accepts GET), and it forced every
  // single database save/load through this extra network-first wrapper. On a
  // slow or unstable mobile connection that adds real latency and retry
  // overhead to every interaction in the app — typing, saving, opening a tab —
  // which is exactly when this started going wrong.
  let sameOriginGet = false;
  try {
    sameOriginGet = e.request.method === 'GET' && new URL(url).origin === self.location.origin;
  } catch (err) { /* leave sameOriginGet false — treat as "not ours", pass through */ }

  if (!sameOriginGet) return; // let the browser handle it normally, no interception

  e.respondWith(
    fetch(e.request)
      .then((response) => {
        if (response && response.ok) {
          caches.open(CACHE_NAME).then((cache) => cache.put(e.request, response.clone()));
        }
        return response;
      })
      .catch(() => caches.match(e.request))
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
