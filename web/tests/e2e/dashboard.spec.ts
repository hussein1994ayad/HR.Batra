import { expect, test, type Page } from '@playwright/test';
import { ADMIN, mockSupabase } from './mock-supabase';

function collectPageErrors(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (err) => errors.push(err.message));
  return errors;
}

test.describe('authentication', () => {
  test('redirects to login when there is no session', async ({ page }) => {
    await mockSupabase(page, { loggedIn: false });
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole('heading', { name: 'تسجيل الدخول' })).toBeVisible();
  });

  test('shows an error for wrong credentials and signs in with valid ones', async ({ page }) => {
    await mockSupabase(page, { loggedIn: false });
    await page.goto('/login');
    await page.getByLabel('البريد الإلكتروني', { exact: true }).fill(ADMIN.email);
    await page.getByLabel('كلمة المرور', { exact: true }).fill('wrong-password');
    await page.getByRole('button', { name: /الدخول إلى لوحة التحكم/ }).click();
    await expect(page.getByText('بيانات الدخول غير صحيحة')).toBeVisible();

    await page.getByLabel('كلمة المرور', { exact: true }).fill(ADMIN.password);
    await page.getByRole('button', { name: /الدخول إلى لوحة التحكم/ }).click();
    await expect(page).toHaveURL(/\/dashboard$/);
  });
});

test.describe('overview', () => {
  test('greets the admin and summarises today', async ({ page }) => {
    const errors = collectPageErrors(page);
    await mockSupabase(page);
    await page.goto('/dashboard');

    // داخل محتوى الصفحة فقط: اسم المستخدم أسفل القائمة الجانبية (h4) يظهر بعد تحميل الجلسة
    await expect(page.getByRole('main').getByRole('heading', { name: /صباح الخير|مساء الخير|أهلاً/ }).filter({ hasText: 'حسين' })).toBeVisible();
    // One of three active employees checked in; the other two are due and absent.
    await expect(page.getByText('نسبة الحضور')).toBeVisible();
    await expect(page.locator('#absent-section')).toContainText('مصطفى حسن');
    await expect(page.getByText('Fake GPS')).toBeVisible();
    expect(errors).toEqual([]);
  });

  test('quick navigator (Ctrl+K) jumps to a page', async ({ page }) => {
    await mockSupabase(page);
    await page.goto('/dashboard');
    // داخل محتوى الصفحة فقط: اسم المستخدم أسفل القائمة الجانبية (h4) يظهر بعد تحميل الجلسة
    await expect(page.getByRole('main').getByRole('heading', { name: /صباح الخير|مساء الخير|أهلاً/ }).filter({ hasText: 'حسين' })).toBeVisible();
    await page.keyboard.press('Control+k');
    await page.getByPlaceholder('ابحث عن صفحة أو قسم...').fill('الرواتب');
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(/\/dashboard\/payroll$/);
  });

  test('marks notifications as read', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard');
    await page.getByRole('button', { name: 'الإشعارات' }).click();
    await expect(page.getByText('قدّم موظف طلب إجازة')).toBeVisible();
    await page.getByRole('button', { name: 'تحديد الكل كمقروء' }).click();
    await expect.poll(() => api.writes('notifications', 'PATCH').length).toBe(1);
    expect(api.writes('notifications', 'PATCH')[0].body).toEqual({ is_read: true });
  });

  test('sends a targeted announcement', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard');
    await page.getByRole('button', { name: 'بث تعميم' }).first().click();
    await page.getByRole('tab', { name: /موظفون محددون/ }).click();
    await page.getByLabel('زينب علي').check();
    await page.getByPlaceholder('اكتب نص التعميم هنا...').fill('اجتماع الساعة 10');
    await page.getByRole('button', { name: 'إرسال التعميم' }).click();
    await expect.poll(() => api.writes('notifications', 'POST').length).toBe(1);
    const body = api.writes('notifications', 'POST')[0].body as Array<{ employee_id: string; body: string }>;
    expect(body).toHaveLength(1);
    expect(body[0]).toMatchObject({ employee_id: 'e1', body: 'اجتماع الساعة 10' });
  });
});

const PAGES: Array<{ path: string; heading: string }> = [
  { path: '/dashboard/employees', heading: 'الموظفون والأجهزة' },
  { path: '/dashboard/tracking', heading: 'الحضور والتتبع' },
  { path: '/dashboard/geofences', heading: 'الفروع والسياج الجغرافي' },
  { path: '/dashboard/leaves', heading: 'الإجازات' },
  { path: '/dashboard/loans', heading: 'السلف والأقساط' },
  { path: '/dashboard/payroll', heading: 'الرواتب والمكافآت' },
  { path: '/dashboard/trash', heading: 'سلة المحذوفات' },
  { path: '/dashboard/storage', heading: 'التخزين والمساحة' },
  { path: '/dashboard/settings', heading: 'الإعدادات' },
];

for (const p of PAGES) {
  test(`renders ${p.path} without runtime errors`, async ({ page }) => {
    const errors = collectPageErrors(page);
    await mockSupabase(page);
    await page.goto(p.path);
    await expect(page.getByRole('main').getByRole('heading', { level: 2, name: p.heading, exact: true })).toBeVisible();
    await expect(page.locator('[aria-current="page"]').first()).toBeVisible();
    expect(errors).toEqual([]);
  });
}

test.describe('workflows', () => {
  test('approves a leave request as unpaid', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/leaves');
    await expect(page.getByText('سفر عائلي')).toBeVisible();
    await page.getByRole('switch').click(); // paid → unpaid
    await page.getByRole('button', { name: 'موافقة' }).click();

    await expect.poll(() => api.writes('leave_requests', 'PATCH').length).toBe(1);
    expect(api.writes('leave_requests', 'PATCH')[0].body).toMatchObject({ status: 'approved', is_paid: false, approved_by: ADMIN.id });
    await expect(page.getByText('سفر عائلي')).toBeHidden();
    // إشعار الموظف يرسله trigger قاعدة البيانات، فلا تكتبه الصفحة (كان يصل مكرراً)
    expect(api.writes('notifications', 'POST')).toHaveLength(0);
  });

  test('asks for confirmation before rejecting a loan', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/loans');
    await page.getByRole('button', { name: 'رفض' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('رفض طلب السلفة؟');
    await dialog.getByRole('button', { name: 'إلغاء' }).click();
    expect(api.writes('loans', 'PATCH')).toHaveLength(0);

    await page.getByRole('button', { name: 'رفض' }).click();
    await page.getByRole('dialog').getByRole('textbox').fill('تجاوز الحد المسموح');
    await page.getByRole('dialog').getByRole('button', { name: 'رفض الطلب' }).click();
    await expect.poll(() => api.writes('loans', 'PATCH').length).toBe(1);
    expect(api.writes('loans', 'PATCH')[0].body).toMatchObject({ status: 'rejected', rejection_reason: 'تجاوز الحد المسموح' });
  });

  test('approves a loan and generates the installment schedule', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/loans');
    await page.getByRole('button', { name: 'اعتماد وجدولة' }).click();
    await expect(page.getByRole('dialog')).toContainText('100,000 د.ع');
    await page.getByRole('button', { name: 'حفظ وتوليد الأقساط' }).click();
    // الاعتماد وتوليد الأقساط في معاملة واحدة على السيرفر (approve_loan)
    await expect.poll(() => api.writes('rpc:approve_loan', 'POST').length).toBe(1);
    expect(api.writes('rpc:approve_loan', 'POST')[0].body).toMatchObject({ p_loan_id: 'ln1', p_amount: 600000, p_months: 6 });
    expect(api.writes('loan_installments', 'POST')).toHaveLength(0);
  });

  test('computes and approves a salary', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/payroll');
    const row = page.locator('tr', { hasText: 'زينب علي' });
    // 900,000 + 50,000 bonus − 20,000 deduction − 100,000 loan installment
    await expect(row).toContainText('830,000 د.ع');
    await row.getByRole('button', { name: 'اعتماد' }).click();
    // الكشف والأقساط والقيود تُعتمد في معاملة واحدة على السيرفر (approve_salary_slip)
    await expect.poll(() => api.writes('rpc:approve_salary_slip', 'POST').length).toBe(1);
    expect(api.writes('rpc:approve_salary_slip', 'POST')[0].body).toMatchObject({
      p_employee_id: 'e1', p_basic_salary: 900000, p_net_salary: 830000, p_loans_deduction: 100000, p_installment_ids: ['i2'],
    });
  });

  test('opens the add-employee form from the overview and never shows passwords', async ({ page }) => {
    await mockSupabase(page);
    await page.goto('/dashboard');
    await page.getByRole('link', { name: 'إضافة موظف' }).first().click();
    await expect(page.getByRole('dialog')).toContainText('إضافة موظف جديد');
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog')).toBeHidden();

    // كلمات السر لا تُحفظ مقروءة ولا تُعرض (حتى لو رجعها السيرفر القديم)
    const row = page.locator('tr', { hasText: 'زينب علي' });
    await expect(row).toBeVisible();
    await expect(row).not.toContainText('Zz123456');
    await expect(row.getByTitle('إظهار')).toHaveCount(0);
  });

  test('approves a pending device', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/employees');
    await expect(page.getByText('Galaxy S24')).toBeVisible();
    await page.getByRole('button', { name: 'اعتماد' }).click();
    await expect.poll(() => api.writes('employee_devices', 'PATCH').length).toBe(1);
    await expect.poll(() => api.writes('employees', 'PATCH').length).toBe(1);
    expect(api.writes('employees', 'PATCH')[0].body).toEqual({ device_id_lock: 'dev-2' });
  });

  test('records an absence decision from the attendance page', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/tracking');
    await page.getByRole('tab', { name: /قرارات الغياب والتأخير/ }).click();
    const row = page.locator('tr', { hasText: 'مصطفى حسن' });
    await row.getByRole('button', { name: 'تطبيق' }).click();
    await expect.poll(() => api.writes('attendance', 'POST').length).toBe(1);
    expect(api.writes('attendance', 'POST')[0].body).toMatchObject({ employee_id: 'e2', status: 'absent', deduction_status: 'applied' });
    expect(api.writes('bonuses_deductions', 'POST')[0].body).toMatchObject({ employee_id: 'e2', type: 'deduction', amount: 25000 });
  });

  test('saves settings', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/settings');
    await page.getByLabel('يوم البداية').fill('1');
    await page.getByLabel('يوم النهاية').fill('30');
    await page.getByRole('button', { name: 'حفظ الإعدادات' }).click();
    await expect.poll(() => api.writes('system_settings', 'POST').length).toBe(1);
    const saved = api.writes('system_settings', 'POST')[0].body as Array<{ key: string; value: Record<string, number> }>;
    expect(saved.find((s) => s.key === 'payroll_policy')?.value).toEqual({ cycle_start_day: 1, cycle_end_day: 30 });
  });
});
