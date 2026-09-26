import { defineConfig, devices } from '@playwright/test';

const PORT = 4173;

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  // 'github' يكتب أخطاء الفحوص كتعليقات على الـ PR (تُقرأ بدون تسجيل دخول)
  reporter: process.env.CI ? [['list'], ['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${PORT}`,
    locale: 'ar-IQ',
    timezoneId: 'Asia/Baghdad',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'desktop',
      testIgnore: /responsive\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1440, height: 900 },
        // Reuse a preinstalled Chromium when one is provided (e.g. sandboxed environments).
        launchOptions: process.env.PW_CHROMIUM_PATH ? { executablePath: process.env.PW_CHROMIUM_PATH } : {},
      },
    },
    {
      name: 'mobile',
      testMatch: /responsive\.spec\.ts/,
      use: {
        ...devices['Pixel 7'],
        launchOptions: process.env.PW_CHROMIUM_PATH ? { executablePath: process.env.PW_CHROMIUM_PATH } : {},
      },
    },
  ],
  webServer: {
    command: `node scripts/serve-static.mjs out ${PORT}`,
    url: `http://localhost:${PORT}/login`,
    reuseExistingServer: !process.env.CI,
  },
});
