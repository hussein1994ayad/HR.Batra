import { expect, test, type Page } from '@playwright/test';
import { ADMIN, defaultFixtures, mockSupabase } from './mock-supabase';

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
    expect(errors, `page errors: ${errors.join(' | ')}`).toEqual([]);
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
    await page.getByPlaceholder('مثال: عطلة رسمية يوم الخميس').fill('اجتماع');
    await page.getByPlaceholder('اكتب نص التعميم هنا...').fill('اجتماع الساعة 10');
    await page.getByRole('button', { name: 'بدون نهاية' }).click();
    await page.getByRole('button', { name: 'أسبوع' }).click();
    await page.getByRole('button', { name: 'نشر التعميم' }).click();
    // يُنشر عبر publish_announcement: التعميم + الإشعار + مدة الظهور في خطوة واحدة
    await expect.poll(() => api.writes('rpc:publish_announcement', 'POST').length).toBe(1);
    const body = api.writes('rpc:publish_announcement', 'POST')[0].body as Record<string, unknown>;
    expect(body).toMatchObject({ p_title: 'اجتماع', p_content: 'اجتماع الساعة 10', p_target: 'employees', p_employee_ids: ['e1'] });
    expect(typeof body.p_ends_at).toBe('string');
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
    expect(errors, `page errors: ${errors.join(' | ')}`).toEqual([]);
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

  test('shows the server payroll and approves a salary', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/payroll');
    await expect.poll(() => api.writes('rpc:get_payroll_run', 'POST').length).toBeGreaterThan(0);
    const month = (api.writes('rpc:get_payroll_run', 'POST')[0].body as { p_month: string }).p_month;
    const row = page.locator('tr', { hasText: 'زينب علي' });
    // 900,000 + 50,000 مكافأة − 20,000 خصم − 100,000 قسط سلفة (محسوبة في السيرفر)
    await expect(row).toContainText('830,000 د.ع');
    await expect(page.getByText('المسير مفتوح')).toBeVisible();
    await row.getByRole('button', { name: 'اعتماد' }).click();
    // السيرفر يحسب الكشف ويعتمده؛ الموقع يرسل الموظف والشهر والتعديلات اليدوية فقط
    await expect.poll(() => api.writes('rpc:approve_payroll_slip', 'POST').length).toBe(1);
    expect(api.writes('rpc:approve_payroll_slip', 'POST')[0].body).toEqual({ p_employee_id: 'e1', p_month: month, p_adjustments: [] });
    expect(api.writes('rpc:approve_salary_slip', 'POST')).toHaveLength(0);
  });

  test('decides a pending late event from the payroll details', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/payroll');
    const row = page.locator('tr', { hasText: 'مصطفى حسن' });
    await expect(row).toContainText('بانتظار قرار (1)');
    await row.getByRole('button', { name: 'تفاصيل الحضور والخصم' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('تأخير 40 دقيقة');
    await dialog.getByRole('button', { name: 'إعفاء' }).click();
    // قرار مالي: نافذة تأكيد أولاً، وما ينكتب شي قبلها
    const confirmDialog = page.getByRole('dialog').filter({ hasText: 'إعفاء من هذه الحركة؟' });
    await expect(confirmDialog).toBeVisible();
    expect(api.writes('rpc:decide_payroll_event', 'POST')).toHaveLength(0);
    await confirmDialog.getByRole('button', { name: 'إعفاء' }).click();
    await expect.poll(() => api.writes('rpc:decide_payroll_event', 'POST').length).toBe(1);
    expect(api.writes('rpc:decide_payroll_event', 'POST')[0].body).toMatchObject({ p_event_id: 'pe4', p_approve: false });
    // نافذة التفاصيل تبقى مفتوحة بعد القرار
    await expect(page.getByRole('dialog').filter({ hasText: 'تأخير 40 دقيقة' })).toBeVisible();
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
    // المبلغ يحسبه محرّك الرواتب من سجل الحضور: لا قيد خصم منفصل (كان يُخصم مرتين)
    expect(api.writes('bonuses_deductions', 'POST')).toHaveLength(0);
  });

  test('edits an advance in one server call (no doubled installments)', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/loans');
    await page.getByRole('button', { name: 'جدول الأقساط' }).first().click();
    await page.getByRole('button', { name: 'تعديل السلفة وإعادة الجدولة' }).click();
    await page.getByRole('button', { name: 'حفظ وإعادة الجدولة' }).click();
    await expect.poll(() => api.writes('rpc:reschedule_loan', 'POST').length).toBe(1);
    expect(api.writes('rpc:reschedule_loan', 'POST')[0].body).toMatchObject({ p_loan_id: 'ln2', p_amount: 300000, p_installment_amount: 100000, p_count: 3 });
    // الطريقة القديمة كانت تحذف الأقساط ثم تضيف جدولاً جديداً من المتصفح
    expect(api.writes('loan_installments', 'DELETE')).toHaveLength(0);
    expect(api.writes('loan_installments', 'POST')).toHaveLength(0);
  });

  test('a branch manager does not see admin-only pages', async ({ page }) => {
    const fixtures = defaultFixtures();
    fixtures.employees = fixtures.employees.map((e) => (e.id === ADMIN.id ? { ...e, role: 'manager' } : e));
    await mockSupabase(page, { fixtures });
    await page.goto('/dashboard');
    const nav = page.getByRole('navigation').first();
    await expect(nav.getByRole('link', { name: /الحضور والتتبع/ })).toBeVisible();
    for (const name of ['الرواتب والمكافآت', 'السلف والأقساط', 'الإعدادات', 'التخزين', 'سلة المحذوفات']) {
      await expect(nav.getByRole('link', { name: new RegExp(name) })).toHaveCount(0);
    }
    // فتح صفحة الرواتب بالرابط مباشرة يرجع للرئيسية
    await page.goto('/dashboard/payroll');
    await expect(page).toHaveURL(/\/dashboard\/?$/);
    // صفحة الموظفين مسموحة، لكن بدون زر الحذف/الأرشفة
    await page.goto('/dashboard/employees');
    await expect(page.getByRole('button', { name: 'الملف والوثائق' }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'حذف أو أرشفة الموظف' })).toHaveCount(0);
  });

  test('saves settings', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/settings');
    await page.getByLabel('يوم قطع المسير').fill('25');
    await page.getByLabel('يوم صرف الرواتب').fill('28');
    await page.getByRole('button', { name: 'حفظ الإعدادات' }).click();
    await expect.poll(() => api.writes('rpc:set_payroll_policy', 'POST').length).toBe(1);
    expect(api.writes('rpc:set_payroll_policy', 'POST')[0].body).toEqual({
      p_cutoff_day: 25, p_payment_day: 28, p_overtime_enabled: false, p_overtime_multiplier: 1, p_overtime_min_minutes: 30,
    });
    // سياسة الرواتب لا تُكتب مباشرة (كانت تمسح بقية الإعدادات)
    const saved = api.writes('system_settings', 'POST')[0].body as Array<{ key: string }>;
    expect(saved.some((s) => s.key === 'payroll_policy')).toBe(false);
  });
});
