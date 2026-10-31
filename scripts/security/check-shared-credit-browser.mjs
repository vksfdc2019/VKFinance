// Receives only the disposable pilot identity's session over stdin; never existing user credentials.
import { createRequire } from 'node:module';
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
  await page.goto(site + '/accounts');
  const facility = page.getByRole('article', { name: 'Pilot shared facility shared facility', exact: true });
  await expect(facility.getByText('₹2,50,000', { exact: true })).toBeVisible({ timeout: 30000 });
  await page.getByRole('button', { name: 'Edit Pilot shared facility', exact: true }).click();
  await page.getByLabel('Shared credit limit', { exact: true }).fill('350000');
  await page.getByRole('button', { name: 'Save shared limit', exact: true }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0, { timeout: 30000 });
  await expect(facility.getByText('₹3,00,000', { exact: true })).toBeVisible();
  if (!(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))) throw new Error('Live shared-credit page overflows the phone viewport.');
  await page.screenshot({ path: 'docs/shared-credit-limits/Live_Phone.png', fullPage: true });
  console.log(JSON.stringify({ liveSharedLimitEdited: true, phoneLayout: true }));
} finally { await browser.close(); }
