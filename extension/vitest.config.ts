import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    exclude: [
      'node_modules',
      '.output',
      '.wxt',
      'e2e/**',
      '../.vfox/**',
      '../mobile/build/**',
    ],
    root: fileURLToPath(new URL('./', import.meta.url)),
  },
});
