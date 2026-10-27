import { test, expect } from '@playwright/test';

// Runs against the built dist/ with no Salesforce backend: a signed-out visitor
// must always land on the sign-in page.
test.describe('VK Finance portal (signed out)', () => {
  test('home redirects to sign in', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('Sign in', { exact: true }).first()).toBeVisible();
    await expect(page.getByLabel('Username')).toBeVisible();
    await expect(page.getByLabel('Password')).toBeVisible();
  });

  test('forgot password page is reachable', async ({ page }) => {
    await page.goto('/login');
    await page.getByRole('link', { name: 'Forgot your password?' }).click();
    await expect(page.getByLabel('Username or email')).toBeVisible();
  });
});
