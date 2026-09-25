import { expect, test } from '@playwright/test';
import { mockSupabase } from './mock-supabase';

test('mobile layout: drawer navigation and no horizontal overflow', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /حسين/ })).toBeVisible();

  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);

  await page.getByRole('button', { name: 'فتح القائمة' }).click();
  await page.getByRole('link', { name: 'الإجازات' }).last().click();
  await expect(page).toHaveURL(/\/dashboard\/leaves$/);
  await expect(page.getByRole('heading', { level: 2, name: 'الإجازات' })).toBeVisible();
});
