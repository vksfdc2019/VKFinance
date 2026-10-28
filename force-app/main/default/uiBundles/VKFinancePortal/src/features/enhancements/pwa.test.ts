import { describe, expect, it, vi } from 'vitest';
import { appBasePath, prepareInstall } from './pwa';
import worker from '../../../public/vkf-sw.js?raw';

describe('PWA isolation', () => {
  it('accepts valid same-app manifest JSON with Salesforce generic MIME while retaining worker/offline validation', async () => {
    const originalWorker = Object.getOwnPropertyDescriptor(
      navigator,
      'serviceWorker'
    );
    const register = vi.fn().mockResolvedValue({});
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: { register },
    });
    vi.stubGlobal('isSecureContext', true);
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        headers: { get: () => 'application/octet-stream;type=unknown' },
        json: async () => ({ name: 'VK Finance', start_url: './' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        headers: { get: () => 'application/javascript' },
      })
      .mockResolvedValueOnce({
        ok: true,
        text: async () => '<meta name="vkf-offline" content="public-only">',
      });
    vi.stubGlobal('fetch', fetchMock);
    try {
      await prepareInstall('/VKFinancePortal/');
      expect(register).toHaveBeenCalledWith(
        new URL('/VKFinancePortal/vkf-sw.js', location.origin).href,
        { scope: '/VKFinancePortal/', updateViaCache: 'none' }
      );
      expect(fetchMock).toHaveBeenCalledTimes(3);
    } finally {
      document.querySelector('link[data-vkf-manifest]')?.remove();
      if (originalWorker)
        Object.defineProperty(navigator, 'serviceWorker', originalWorker);
      else Reflect.deleteProperty(navigator, 'serviceWorker');
      vi.unstubAllGlobals();
    }
  });
  it('refuses to cache a hosting fallback in place of the public offline page', async () => {
    let install: (event: {
      waitUntil: (promise: Promise<void>) => void;
    }) => void = () => {};
    const cache = { put: vi.fn() };
    const storage = { open: vi.fn().mockResolvedValue(cache) };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      text: async () => '<html>Platform fallback</html>',
    });
    const scope = {
      registration: { scope: 'https://example.test/VKFinancePortal/' },
      location: { origin: 'https://example.test' },
      addEventListener: (name: string, handler: typeof install) => {
        if (name === 'install') install = handler;
      },
    };
    new Function('self', 'caches', 'fetch', 'URL', 'Response', worker)(
      scope,
      storage,
      fetchMock,
      URL,
      class {}
    );
    let pending: Promise<void> = Promise.resolve();
    install({
      waitUntil: promise => {
        pending = promise;
      },
    });
    await expect(pending).rejects.toThrow(/public offline notice/);
    expect(storage.open).not.toHaveBeenCalled();
    expect(cache.put).not.toHaveBeenCalled();
  });
  it('limits installation scope to the portal basename', () => {
    expect(appBasePath('/VKFinancePortal/enhancements/install')).toBe(
      '/VKFinancePortal/'
    );
    expect(appBasePath('/enhancements/install')).toBe('/');
    expect(appBasePath('/anything', '/lwr/application/vkf')).toBe(
      '/lwr/application/vkf/'
    );
    expect(() => appBasePath('/anything', '//elsewhere.test')).toThrow();
  });
  it('does not intercept API requests, files or writes, and does not cache online navigation', async () => {
    const handlers: Record<
      string,
      (event: {
        request?: unknown;
        respondWith?: ReturnType<typeof vi.fn>;
        waitUntil?: ReturnType<typeof vi.fn>;
      }) => void
    > = {};
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    const cache = { add: vi.fn(), match: vi.fn() };
    const cachesMock = {
      open: vi.fn().mockResolvedValue(cache),
      keys: vi.fn().mockResolvedValue([]),
    };
    const selfMock = {
      registration: { scope: 'https://example.test/VKFinancePortal/' },
      location: { origin: 'https://example.test' },
      addEventListener: (name: string, handler: (typeof handlers)[string]) => {
        handlers[name] = handler;
      },
    };
    new Function(
      'self',
      'caches',
      'fetch',
      'URL',
      'Request',
      'Response',
      worker
    )(selfMock, cachesMock, fetchMock, URL, class {}, class {});
    for (const request of [
      {
        method: 'GET',
        mode: 'cors',
        url: 'https://example.test/services/apexrest/vkf/v1/accounts',
      },
      {
        method: 'POST',
        mode: 'navigate',
        url: 'https://example.test/VKFinancePortal/anything',
      },
      {
        method: 'GET',
        mode: 'no-cors',
        url: 'https://example.test/VKFinancePortal/receipt.jpg',
      },
      {
        method: 'GET',
        mode: 'navigate',
        url: 'https://example.test/another-site/',
      },
    ]) {
      const respondWith = vi.fn();
      handlers.fetch({ request, respondWith });
      expect(respondWith).not.toHaveBeenCalled();
    }
    const respondWith = vi.fn();
    handlers.fetch({
      request: {
        method: 'GET',
        mode: 'navigate',
        url: 'https://example.test/VKFinancePortal/goals',
      },
      respondWith,
    });
    expect(respondWith).toHaveBeenCalledOnce();
    await respondWith.mock.calls[0][0];
    expect(cachesMock.open).not.toHaveBeenCalled();
  });
});
