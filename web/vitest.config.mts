import { defineConfig } from 'vitest/config';
import path from 'node:path';

export default defineConfig({
  resolve: {
    alias: { '@': path.resolve(__dirname, 'src') },
  },
  test: {
    include: ['tests/unit/**/*.test.ts'],
    environment: 'node',
    // Payroll/attendance logic is date based; pin the timezone to the one the company runs in.
    env: { TZ: 'Asia/Baghdad' },
  },
});
