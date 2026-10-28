// Read-only public hosting check in an isolated browser context; no family login.
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../force-app/main/default/uiBundles/VKFinancePortal/package.json', import.meta.url));
const { chromium } = require('@playwright/test');
const site = process.env.VKF_SITE ?? 'https://orgfarm-db588f31ab-dev-ed.develop.my.site.com/VKFinancePortal';
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.goto(site + '/login', { waitUntil: 'domcontentloaded' });
  await page.getByLabel('Username').waitFor();
  await page.evaluate(() => {
    const link = document.createElement('link'); link.rel = 'manifest';
    link.href = new URL('manifest.json', document.baseURI).href; document.head.append(link);
  });
  const client = await page.context().newCDPSession(page);
  const manifest = await client.send('Page.getAppManifest');
  const worker = await page.evaluate(async () => {
    try {
      const base = new URL('./', document.baseURI);
      const reg = await navigator.serviceWorker.register(new URL('vkf-sw.js', base), { scope: base.pathname });
      await Promise.race([navigator.serviceWorker.ready, new Promise((_, reject) => setTimeout(() => reject(new Error('Worker activation timed out')), 12000))]);
      const keys = await caches.keys();
      const cachedUrls = [];
      for (const key of keys.filter(k => k.startsWith('vkf-offline-'))) {
        const cache = await caches.open(key); cachedUrls.push(...(await cache.keys()).map(r => r.url)); await caches.delete(key);
      }
      await reg.unregister();
      return { active: true, cachedUrls };
    } catch (e) { return { active: false, error: String(e.message) }; }
  });
  console.log(JSON.stringify({ signInPage: true, manifest: { url: manifest.url, errors: manifest.errors, parsed: !!manifest.data }, worker }));
} finally { await browser.close(); }
