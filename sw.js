const CACHE_NAME = 'school-ms-cache-v5';
const APP_SHELL = [
  './', './index.html', './manifest.json', './icon-192.png', './icon-512.png',
  // split app files (css + js)
  './css/style.css',
  './css/paper.css',
  './js/core.js',
  './js/auth.js',
  './js/data.js',
  './js/search-alerts.js',
  './js/settings.js',
  './js/dashboard.js',
  './js/students.js',
  './js/teachers.js',
  './js/timetable.js',
  './js/class-logins-view.js',
  './js/finance.js',
  './js/reports.js',
  './js/admission-register.js',
  './js/datesheet.js',
  './js/dmc.js',
  './js/marks-sheet.js',
  './js/papers.js',
  './js/class-portal.js',
  './js/notices.js',
  './js/diary-portal.js',
  './js/parent-portal.js',
  './js/chat.js',
  './js/main.js'
];
const SHELL_TIMEOUT_MS = 4000;

// The DMC print window loads its fonts from this exact stylesheet URL (it differs from the one
// index.html uses for the app itself). Fonts are only cached after a first online use of a URL, so
// the first certificate printed with no signal would fall back to a plain font. Caching this
// stylesheet and its latin/arabic font files at install time fixes that. Keep it identical to the
// font <link> inside DMC_PRINT_HEAD in index.html.
const DMC_FONT_CSS = 'https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600;9..144,700&family=Berkshire+Swash&family=Aref+Ruqaa:wght@400;700&family=Inter:wght@400;500;600;700&display=swap';
const DMC_FONT_SUBSETS = ['latin', 'arabic'];   // skip the other language subsets to keep the download small

// Returns the font file URLs (only the wanted subsets) listed in a Google Fonts stylesheet.
function fontFileUrls(css) {
  const out = [];
  const re = /\/\*\s*([a-z-]+)\s*\*\/\s*@font-face\s*\{[^}]*?url\((https:\/\/fonts\.gstatic\.com\/[^)]+)\)/g;
  let m;
  while ((m = re.exec(css))) if (DMC_FONT_SUBSETS.includes(m[1]) && !out.includes(m[2])) out.push(m[2]);
  return out;
}

function precacheDmcFonts(cache) {
  return cache.match(DMC_FONT_CSS).then((hit) => hit || fetch(DMC_FONT_CSS).then((res) => {
    if (!res || !res.ok) return null;
    return cache.put(DMC_FONT_CSS, res.clone()).then(() => res);
  })).then((res) => res ? res.text() : '').then((css) =>
    Promise.all(fontFileUrls(css).map((url) =>
      cache.match(url).then((hit) => {
        if (hit) return;
        return fetch(url).then((r) => { if (r && (r.ok || r.type === 'opaque')) return cache.put(url, r); });
      }).catch(() => {})
    ))
  ).catch(() => {});
}
const PRECACHE_LIBS = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.js',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js',
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js',
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js',
  'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'
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
        ),
        precacheDmcFonts(cache)
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
        cache.match(e.request, { ignoreVary: true }).then((cached) => {
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
