import { test, expect } from '@playwright/test';
import { Buffer } from 'node:buffer';
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() =>
    sessionStorage.setItem('vkf.session', 'local-preview-only')
  );
});

test('Discover and savings goals work at desktop and phone widths', async ({
  page,
}) => {
  await page.goto('/enhancements');
  await expect(
    page.getByRole('heading', { name: 'Small steps.' })
  ).toBeVisible();
  await page.screenshot({
    path: 'test-results/phase6-discover-desktop.png',
    fullPage: true,
  });
  await page
    .getByRole('article')
    .filter({
      has: page.getByRole('heading', { name: 'Savings goals', exact: true }),
    })
    .getByRole('link', { name: 'Explore', exact: true })
    .click();
  await expect(
    page.getByRole('heading', { name: 'A family holiday', exact: true })
  ).toBeVisible();
  await page.screenshot({
    path: 'test-results/phase6-goals-desktop.png',
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    page.getByRole('heading', { name: 'Give your savings a purpose' })
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: 'test-results/phase6-goals-phone.png',
    fullPage: true,
  });
});

test('statement import requires review and a separate explicit start', async ({
  page,
}) => {
  await page.goto('/enhancements/imports');
  await page.getByLabel('Upload statement CSV').setInputFiles({
    name: 'bank.csv',
    mimeType: 'text/csv',
    buffer: Buffer.from('Date,Description,Amount\n2026-10-28,Groceries,-125\n'),
  });
  await page
    .getByRole('combobox', { name: 'Account', exact: true })
    .selectOption('a1');
  await page.getByRole('button', { name: 'Review entries' }).click();
  await page
    .getByRole('combobox', { name: 'Expense / refund category' })
    .selectOption('c1');
  await page.getByRole('button', { name: 'Save 1 reviewed rows' }).click();
  await expect(page.getByText('Your reviewed rows are saved.')).toBeVisible();
  await page.getByRole('button', { name: 'Start import', exact: true }).click();
  await expect(
    page.getByText(
      'Finished. Your ledger and balances now include the imported entries.'
    )
  ).toBeVisible();
});

test('parent approval is confirmed and insights can be snoozed', async ({
  page,
}) => {
  await page.goto('/enhancements/requests');
  await page.getByRole('button', { name: 'Approve', exact: true }).click();
  await expect(page.getByRole('dialog')).toContainText(
    'does not change account balances'
  );
  await page.getByRole('button', { name: 'Confirm', exact: true }).click();
  await expect(
    page.getByRole('button', { name: 'Record purchase', exact: true })
  ).toBeVisible();
  await page.goto('/enhancements/insights');
  await expect(
    page.getByRole('heading', { name: 'Dining out is running ahead' })
  ).toBeVisible();
  await page
    .getByRole('article')
    .first()
    .getByRole('button', { name: 'Snooze 7 days' })
    .click();
  await expect(
    page.getByRole('heading', { name: 'Dining out is running ahead' })
  ).toHaveCount(0);
});

test('receipt and installation pages explain their connected workflows', async ({
  page,
}) => {
  await page.goto('/enhancements/receipts');
  await expect(
    page.getByRole('heading', { name: 'A place for every receipt' })
  ).toBeVisible();
  await page.goto('/enhancements/install');
  await expect(
    page.getByRole('heading', { name: 'Make room on your home screen' })
  ).toBeVisible();
  await page
    .getByRole('button', { name: 'Set up home-screen installation' })
    .click();
  await expect(
    page.getByRole('button', { name: 'Install setup ready' })
  ).toBeVisible();
  const names = await page.evaluate(async () => await caches.keys());
  expect(names.every(n => n.startsWith('vkf-offline-'))).toBe(true);
});

test('credit card shows linked bill and all five amounts on desktop and phone', async ({
  page,
}) => {
  await page.goto('/accounts');
  const card = page
    .getByRole('article')
    .filter({
      has: page.getByRole('heading', { name: 'AXIS BANK NEO', exact: true }),
    });
  for (const label of [
    'Total outstanding',
    'Available amount',
    'Bill amount',
    'Total credit limit',
    'Bill due date',
  ]) {
    await expect(card.getByText(label, { exact: true })).toBeVisible();
  }
  for (const value of [
    '₹29,613.72',
    '₹2,84,386.28',
    '₹16,985.59',
    '₹3,14,000',
    '4 Nov',
  ]) {
    await expect(card.getByText(value, { exact: true })).toBeVisible();
  }
  await expect(card).not.toContainText('Nothing to pay');
  await page.screenshot({
    path: 'test-results/card-bill-desktop.png',
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(card.getByText('₹16,985.59', { exact: true })).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await card.screenshot({ path: 'test-results/card-bill-phone.png' });
});
