import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
    // الحسابات تعتمد على التوقيت المحلي (أيام الأسبوع وحدود اليوم) — ثبّته على بغداد
    env: { TZ: 'Asia/Baghdad' },
  },
});
