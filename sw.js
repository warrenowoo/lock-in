// Lock-In service worker — offline support + reliable updates
const CACHE = 'lockin-v2';
const ASSETS = ['./', './index.html', './manifest.json', './icon-180.png', './icon-192.png', './icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      // {cache:'reload'} bypasses the browser HTTP cache so we always grab fresh files
      .then(c => Promise.all(ASSETS.map(u => c.add(new Request(u, {cache: 'reload'})).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  // Network-first for the page itself, bypassing the HTTP cache so fixes land immediately.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req.url, {cache: 'no-store'}).then(resp => {
        const copy = resp.clone();
        caches.open(CACHE).then(c => c.put('./index.html', copy));
        return resp;
      }).catch(() => caches.match('./index.html'))
    );
    return;
  }
  // Cache-first for everything else (icons, manifest).
  e.respondWith(caches.match(req).then(r => r || fetch(req)));
});
