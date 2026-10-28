/* VK Finance: cache only this public offline notice. Never cache financial responses. */
const VKF_CACHE = 'vkf-offline-v1-' + new URL(self.registration.scope).pathname;
const VKF_OFFLINE = new URL('vkf-offline.html', self.registration.scope).href;
self.addEventListener('install', event => {
  event.waitUntil(
    fetch(VKF_OFFLINE, { credentials: 'omit', cache: 'no-store' }).then(
      async response => {
        const html = await response.text();
        if (
          !response.ok ||
          !html.includes('name="vkf-offline" content="public-only"')
        ) {
          throw new Error(
            'The public offline notice is not available at this hosting path.'
          );
        }
        const cache = await caches.open(VKF_CACHE);
        await cache.put(
          VKF_OFFLINE,
          new Response(html, {
            headers: { 'Content-Type': 'text/html; charset=utf-8' },
          })
        );
      }
    )
  );
});
self.addEventListener('activate', event => {
  const prefix = 'vkf-offline-';
  const suffix = '-' + new URL(self.registration.scope).pathname;
  event.waitUntil(
    caches
      .keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(
              key =>
                key.startsWith(prefix) &&
                key.endsWith(suffix) &&
                key !== VKF_CACHE
            )
            .map(key => caches.delete(key))
        )
      )
  );
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  // API calls, SDK requests, images, scripts, uploads and mutations always use the network.
  if (
    request.method !== 'GET' ||
    request.mode !== 'navigate' ||
    url.origin !== self.location.origin ||
    !url.href.startsWith(self.registration.scope) ||
    /\/services\/|\/aura\b|\/webruntime\//i.test(url.pathname)
  )
    return;
  event.respondWith(
    fetch(request).catch(async () => {
      const cache = await caches.open(VKF_CACHE);
      return (
        (await cache.match(VKF_OFFLINE)) ||
        new Response('You are offline. Reconnect to use VK Finance.', {
          status: 503,
          headers: {
            'Content-Type': 'text/plain',
            'Cache-Control': 'no-store',
          },
        })
      );
    })
  );
});
