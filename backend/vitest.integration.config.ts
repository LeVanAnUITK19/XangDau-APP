import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/health.test.ts'],
    testTimeout: 10000,
  },
});
