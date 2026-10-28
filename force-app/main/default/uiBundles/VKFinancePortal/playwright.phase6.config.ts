import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir: './e2e',
  testMatch: 'phase6.spec.ts',
  fullyParallel: false,
  workers: 1,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:5176', trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npx vite --config e2e/phase6.vite.config.ts',
    url: 'http://127.0.0.1:5176',
    reuseExistingServer: !process.env.CI,
    timeout: 60000,
  },
});
