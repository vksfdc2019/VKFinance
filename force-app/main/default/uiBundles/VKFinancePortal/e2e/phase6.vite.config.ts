// Browser-only fixtures. This alias is never included by the production Vite config.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const fixtureDirectory = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  root: path.resolve(fixtureDirectory, '..'),
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(fixtureDirectory, '../src'),
      '@salesforce/platform-sdk': path.resolve(
        fixtureDirectory,
        'phase6Sdk.ts'
      ),
    },
  },
  server: { host: '127.0.0.1', port: 5176, strictPort: true },
});
