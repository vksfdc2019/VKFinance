// Live browser checks receive only disposable pilot credentials over stdin.
import { createRequire } from 'node:module';
import { Buffer } from 'node:buffer';
const require = createRequire(new URL('../../force-app/main/default/uiBundles/VKFinancePortal/package.json', import.meta.url));
const { chromium, expect } = require('@playwright/test');
let input = '';
for await (const chunk of process.stdin) input += chunk;
const { site, token, userAgent } = JSON.parse(input);
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({ userAgent, viewport: { width: 390, height: 844 } });
  await context.addInitScript(value => sessionStorage.setItem('vkf.session', value), token);
  const page = await context.newPage();
  await page.goto(site + '/enhancements/goals');
  await expect(page.getByRole('heading', { name: 'Pilot savings', exact: true })).toBeVisible({ timeout: 30000 });
  if (!(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))) throw new Error('The live phone goals page overflows horizontally.');
  await page.screenshot({ path: 'docs/phase6/Live_Goals_Phone.png', fullPage: true });

  await page.goto(site + '/enhancements/receipts');
  await page.getByRole('button', { name: /Pilot receipt purchase/ }).click();
  const image = await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = 180; canvas.height = 100;
    const drawing = canvas.getContext('2d'); drawing.fillStyle = '#ffffff'; drawing.fillRect(0, 0, 180, 100);
    drawing.fillStyle = '#12334b'; drawing.font = '16px sans-serif'; drawing.fillText('Pilot receipt', 16, 44);
    return canvas.toDataURL('image/png').split(',')[1];
  });
  await page.getByLabel('Attach receipt photo').setInputFiles({ name: 'pilot-browser-receipt.png', mimeType: 'image/png', buffer: Buffer.from(image, 'base64') });
  await page.getByRole('button', { name: /pilot-browser-receipt.jpg/ }).first().click({ timeout: 30000 });
  const photo = page.getByRole('dialog').getByRole('img');
  await expect(photo).toBeVisible();
  await expect.poll(() => photo.evaluate(element => element.naturalWidth)).toBeGreaterThan(0);
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Remove pilot-browser-receipt.jpg', exact: true }).click();
  await page.getByRole('button', { name: 'Remove photo', exact: true }).click();
  await expect(page.getByText('pilot-browser-receipt.jpg', { exact: true })).toHaveCount(0);

  await page.goto(site + '/enhancements/install');
  await page.getByRole('button', { name: 'Set up home-screen installation' }).click();
  await expect(page.getByRole('button', { name: 'Install setup ready' })).toBeVisible({ timeout: 20000 });
  const cdp = await context.newCDPSession(page);
  const manifest = await cdp.send('Page.getAppManifest');
  if (manifest.errors.length || !manifest.data) throw new Error('The live manifest has browser errors.');
  const cached = await page.evaluate(async () => {
    await Promise.race([navigator.serviceWorker.ready, new Promise((_, reject) => setTimeout(() => reject(new Error('Worker activation timeout')), 12000))]);
    const urls = [];
    for (const key of await caches.keys()) {
      if (key.startsWith('vkf-offline-')) {
        const cache = await caches.open(key); urls.push(...(await cache.keys()).map(request => request.url)); await caches.delete(key);
      }
    }
    for (const registration of await navigator.serviceWorker.getRegistrations()) await registration.unregister();
    return urls;
  });
  if (!cached.length || cached.some(url => !url.endsWith('/vkf-offline.html'))) throw new Error('Unexpected live offline cache content.');
  console.log(JSON.stringify({ liveMobileGoals: true, liveReceiptCompressionUploadPreviewDelete: true, authenticatedInstallSetup: true, manifestErrors: 0, offlineCachePublicOnly: true }));
} finally { await browser.close(); }
