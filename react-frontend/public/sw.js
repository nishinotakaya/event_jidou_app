// PWA用 Service Worker
// ビルド不要のプレーンJS（Workboxなし）

const CACHE_VERSION = 'v1';
const CACHE_NAME = `event-kokuchi-cache-${CACHE_VERSION}`;

const NEVER_CACHE_PATH_PREFIXES = ['/api/', '/users/', '/auth/', '/cable', '/uploads/'];

self.addEventListener('install', (installEvent) => {
  self.skipWaiting();
});

self.addEventListener('activate', (activateEvent) => {
  activateEvent.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((cacheName) => cacheName !== CACHE_NAME)
          .map((cacheName) => caches.delete(cacheName))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (fetchEvent) => {
  const request = fetchEvent.request;

  if (request.method !== 'GET') {
    return;
  }

  const requestUrl = new URL(request.url);
  if (requestUrl.origin !== self.location.origin) {
    return;
  }

  if (NEVER_CACHE_PATH_PREFIXES.some((prefix) => requestUrl.pathname.startsWith(prefix))) {
    return;
  }

  if (request.mode === 'navigate') {
    fetchEvent.respondWith(respondNetworkFirstForNavigation(request));
    return;
  }

  if (requestUrl.pathname.startsWith('/assets/')) {
    fetchEvent.respondWith(respondCacheFirst(request));
    return;
  }

  // それ以外はネットワークのみ（respondWithしない）
});

async function respondCacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cachedResponse = await cache.match(request);
  if (cachedResponse) {
    return cachedResponse;
  }
  const networkResponse = await fetch(request);
  if (networkResponse.ok) {
    cache.put(request, networkResponse.clone());
  }
  return networkResponse;
}

async function respondNetworkFirstForNavigation(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const networkResponse = await fetch(request);
    if (networkResponse.ok) {
      cache.put('/index.html', networkResponse.clone());
    }
    return networkResponse;
  } catch (networkError) {
    const cachedIndexHtml = await cache.match('/index.html');
    if (cachedIndexHtml) {
      return cachedIndexHtml;
    }
    throw networkError;
  }
}
