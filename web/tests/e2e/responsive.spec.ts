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

// على الموبايل التبويبات كانت تنقص من الطرف (تتحرك بالسحب بس ماكو شي يدل عليها): لازم كلها تبين.
for (const path of ['leaves', 'payroll', 'settings', 'loans', 'employees']) {
  test(`mobile: every tab on /dashboard/${path} is fully on screen`, async ({ page }) => {
    await mockSupabase(page);
    await page.goto(`/dashboard/${path}`);
    const tabs = page.getByRole('tab');
    await expect(tabs.first()).toBeVisible();
    const width = page.viewportSize()!.width;
    const cut: string[] = [];
    for (const tab of await tabs.all()) {
      const box = await tab.boundingBox();
      if (box && (box.x < 0 || box.x + box.width > width + 1)) cut.push(`${(await tab.innerText()).trim()} @ ${Math.round(box.x)}`);
    }
    expect(cut).toEqual([]);
  });
}
