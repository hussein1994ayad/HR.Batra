import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { strFromU8, unzipSync } from 'fflate';
import { ADMIN, defaultFixtures, mockSupabase, payrollRunFixture } from './mock-supabase';

/** مسير خلصت فترة دوامه (آخر يوم = أمس): الاعتماد متاح. */
function endedPayrollRun() {
  const run = payrollRunFixture().get_payroll_run;
  const day = (offset: number) => {
    const d = new Date();
    d.setDate(d.getDate() + offset);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  };
  return { ...run, period: { ...run.period, start_date: day(-30), cutoff_date: day(-1) } };
}

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

const PAGES: Array<{ path: string; heading: string | RegExp }> = [
  { path: '/dashboard/employees', heading: 'الموظفون والأجهزة' },
  { path: '/dashboard/tracking', heading: 'الحضور والتتبع' },
  { path: '/dashboard/geofences', heading: 'الفروع والسياج الجغرافي' },
  { path: '/dashboard/leaves', heading: 'الإجازات' },
  { path: '/dashboard/loans', heading: 'السلف والأقساط' },
  // صفحة الرواتب عنوانها الشهر بالترتيب: «رواتب الشهر العاشر 2026»
  { path: '/dashboard/payroll', heading: /^رواتب الشهر \S+( عشر)? \d{4}$/ },
  { path: '/dashboard/trash', heading: 'سلة المحذوفات' },
  { path: '/dashboard/storage', heading: 'التخزين والمساحة' },
  { path: '/dashboard/settings', heading: 'الإعدادات' },
];

for (const p of PAGES) {
  test(`renders ${p.path} without runtime errors`, async ({ page }) => {
    const errors = collectPageErrors(page);
    await mockSupabase(page);
    await page.goto(p.path);
    await expect(page.getByRole('main').getByRole('heading', { level: 2, name: p.heading, exact: typeof p.heading === 'string' })).toBeVisible();
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

  test('payroll is calculated with the "calculate" button', async ({ page }) => {
    // 25 موظف = 3 طلبات صغيرة (10 + 10 + 5)، كل وحدة تكمل من آخر موظف انحسب (تدقيق 14/10 BUG-018)
    const batch = (body: { p_after: string | null }) => {
      const done = body.p_after === null ? 10 : body.p_after === 'e10' ? 20 : 25;
      return { total: 25, done, last_id: `e${done}`, finished: done === 25 };
    };
    const api = await mockSupabase(page, { rpc: { calculate_payroll_batch: batch } });
    await page.goto('/dashboard/payroll');
    await expect(page.locator('tr', { hasText: 'زينب علي' })).toContainText('830,000 د.ع');
    expect(api.writes('rpc:calculate_payroll_batch', 'POST')).toHaveLength(0); // فتح الصفحة ما يحسب
    await page.getByRole('button', { name: 'احتساب الرواتب' }).click();
    await expect.poll(() => api.writes('rpc:calculate_payroll_batch', 'POST').length).toBe(3);
    expect(api.writes('rpc:calculate_payroll_batch', 'POST').map((c) => (c.body as { p_after: string | null }).p_after)).toEqual([null, 'e10', 'e20']);
    expect(api.writes('rpc:calculate_payroll', 'POST')).toHaveLength(0);
    // بعد الاحتساب تطلع النتيجة: الصافي والقرارات المعلّقة
    const result = page.getByRole('dialog');
    await expect(result).toContainText('نتيجة احتساب رواتب الشهر');
    await expect(result).toContainText('الصافي اللي ينصرف للموظفين');
    await result.getByRole('button', { name: 'تمام' }).click();
    await expect(result).toBeHidden();
  });

  test('before the database update, the calculate button still works in one request', async ({ page }) => {
    const api = await mockSupabase(page, { rpc: { calculate_payroll_batch: { __error: { code: 'PGRST202', message: 'function not found' } } } });
    await page.goto('/dashboard/payroll');
    await page.getByRole('button', { name: 'احتساب الرواتب' }).click();
    await expect.poll(() => api.writes('rpc:calculate_payroll', 'POST').length).toBe(1);
    await expect(page.getByRole('dialog')).toContainText('نتيجة احتساب رواتب الشهر');
  });

  test('approval waits for the end of the payroll period', async ({ page }) => {
    await mockSupabase(page);
    await page.goto('/dashboard/payroll');
    const row = page.locator('tr', { hasText: 'زينب علي' });
    await expect(row).toContainText('830,000 د.ع');
    // فترة الدوام تنتهي يوم 26: قبلها زر الاعتماد مقفول
    await expect(row.getByRole('button', { name: 'اعتماد' })).toBeDisabled();
  });

  test('shows the server payroll and approves a salary', async ({ page }) => {
    const api = await mockSupabase(page, { rpc: { get_payroll_run: endedPayrollRun() } });
    await page.goto('/dashboard/payroll');
    await expect.poll(() => api.writes('rpc:get_payroll_run', 'POST').length).toBeGreaterThan(0);
    const month = (api.writes('rpc:get_payroll_run', 'POST')[0].body as { p_month: string }).p_month;
    const row = page.locator('tr', { hasText: 'زينب علي' });
    // 900,000 + 50,000 مكافأة − 20,000 خصم − 100,000 قسط سلفة (محسوبة في السيرفر)
    await expect(row).toContainText('830,000 د.ع');
    await expect(page.getByText('المسير مفتوح')).toBeVisible();
    await row.getByRole('button', { name: 'اعتماد' }).click();
    // تأكيد بالصافي قبل الاعتماد، وما ينرسل شي قبله
    const confirmDialog = page.getByRole('dialog').filter({ hasText: 'اعتماد راتب زينب علي؟' });
    await expect(confirmDialog).toContainText('830,000');
    expect(api.writes('rpc:approve_payroll_slip', 'POST')).toHaveLength(0);
    await confirmDialog.getByRole('button', { name: 'اعتماد الراتب' }).click();
    // السيرفر يحسب الكشف ويعتمده؛ الموقع يرسل الموظف والشهر والتعديلات اليدوية فقط
    await expect.poll(() => api.writes('rpc:approve_payroll_slip', 'POST').length).toBe(1);
    expect(api.writes('rpc:approve_payroll_slip', 'POST')[0].body).toEqual({ p_employee_id: 'e1', p_month: month, p_adjustments: [] });
    expect(api.writes('rpc:approve_salary_slip', 'POST')).toHaveLength(0);
  });

  test('decides a pending late event from the payroll details', async ({ page }) => {
    const api = await mockSupabase(page);
    await page.goto('/dashboard/payroll');
    const row = page.locator('tr', { hasText: 'مصطفى حسن' });
    await expect(row).toContainText('1 بانتظار قرارك');
    await row.getByRole('button', { name: 'التفاصيل والقرارات' }).click();
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

  test('records an absence decision from the attendance page, with the amount shown and editable', async ({ page }) => {
    const api = await mockSupabase(page, { rpc: { payroll_day_rates: [{ employee_id: 'e2', daily_rate: 20000 }] } });
    await page.goto('/dashboard/tracking');
    await page.getByRole('tab', { name: /قرارات الغياب والتأخير/ }).click();
    const row = page.locator('tr', { hasText: 'مصطفى حسن' });
    // غياب اليوم ما انحسبت حركته بعد: المبلغ = أجر اليوم
    await expect(row).toContainText('20,000');
    await row.getByRole('button', { name: 'تطبيق' }).click();
    // تأكيد قبل الخصم، والمبلغ المحسوب قابل للتعديل
    const confirmDialog = page.getByRole('dialog').filter({ hasText: 'تطبيق خصم الغياب؟' });
    await expect(confirmDialog).toBeVisible();
    const amount = confirmDialog.getByLabel('مبلغ الخصم (د.ع)');
    await expect(amount).toHaveValue('20,000');
    expect(api.writes('rpc:decide_absence_day', 'POST')).toHaveLength(0);
    await amount.fill('10000');
    await confirmDialog.getByRole('button', { name: 'تطبيق الخصم' }).click();
    await expect.poll(() => api.writes('rpc:decide_absence_day', 'POST').length).toBe(1);
    expect(api.writes('rpc:decide_absence_day', 'POST')[0].body).toMatchObject({ p_employee_id: 'e2', p_approve: true, p_amount: 10000 });
    // السيرفر يسجّل الغياب ويحسب الخصم: لا كتابة مباشرة بالحضور ولا قيد خصم منفصل (كان يُخصم مرتين)
    expect(api.writes('attendance', 'POST')).toHaveLength(0);
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

  test('an offline punch with an unverified time is flagged and can be marked reviewed', async ({ page }) => {
    const fixtures = defaultFixtures();
    fixtures.attendance = fixtures.attendance.map((a) => ({ ...a, check_in_offline: true, check_in_time_source: 'offline_review', check_in_device_time: a.check_in_time }));
    const api = await mockSupabase(page, { fixtures });
    await page.goto('/dashboard/tracking');
    const row = page.locator('tr', { hasText: 'زينب علي' }).first();
    await expect(row).toContainText('بدون إنترنت · تحتاج مراجعة');
    await page.getByRole('button', { name: /بصمة بدون إنترنت تحتاج مراجعة/ }).click();
    await row.getByRole('button', { name: /تمت المراجعة/ }).click();
    await expect.poll(() => api.writes('rpc:mark_offline_punch_reviewed', 'POST').length).toBe(1);
    expect(api.writes('rpc:mark_offline_punch_reviewed', 'POST')[0].body).toMatchObject({ p_attendance_id: 'att1' });
  });

  test('a branch manager decides an absence without seeing or typing any amount', async ({ page }) => {
    const fixtures = defaultFixtures();
    fixtures.employees = fixtures.employees.map((e) => (e.id === ADMIN.id ? { ...e, role: 'manager' } : e));
    // السيرفر ما يعطي المدير أجر اليوم (تدقيق 14/10: المبالغ تكشف الراتب)
    const api = await mockSupabase(page, { fixtures, rpc: { payroll_day_rates: [] } });
    await page.goto('/dashboard/tracking');
    await page.getByRole('tab', { name: /قرارات الغياب والتأخير/ }).click();
    const row = page.locator('tr', { hasText: 'مصطفى حسن' });
    await expect(row).toContainText('يُحسب تلقائياً');
    await row.getByRole('button', { name: 'تطبيق' }).click();
    const confirmDialog = page.getByRole('dialog').filter({ hasText: 'تطبيق خصم الغياب؟' });
    await expect(confirmDialog).toContainText('المبلغ المحسوب');
    await expect(confirmDialog.getByLabel('مبلغ الخصم (د.ع)')).toHaveCount(0);
    await confirmDialog.getByRole('button', { name: 'تطبيق الخصم' }).click();
    await expect.poll(() => api.writes('rpc:decide_absence_day', 'POST').length).toBe(1);
    expect(api.writes('rpc:decide_absence_day', 'POST')[0].body).not.toHaveProperty('p_amount');
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
    await expect(page.getByRole('button', { name: 'إنهاء خدمات الموظف' })).toHaveCount(0);
  });

  test('cleans a closed payroll period: preview with counts, blocked attendance, confirm, one server call', async ({ page }) => {
    const preview = {
      month: '2026-09', start_date: '2026-09-01', end_date: '2026-09-26', status: 'closed', next_month: '2026-10', next_status: 'open',
      checks: { closed: true, next_closed: false, next_delivered: false, pending_decisions: 1 },
      pending_list: [{ employee: 'مصطفى حسن', date: '2026-09-20', type: 'خروج مبكر', amount: 1250 }],
      counts: { attendance: 120, tracking: 5400, stops: 30, violations: 2, notifications: 85 },
      bytes: { attendance: 18360, tracking: 521000, notifications: 21335 },
      done: { attendance: false, tracking: false, notifications: false },
      can: { attendance: false, tracking: true, notifications: true },
      history: [],
    };
    const loans = {
      settled: [{ id: 'ln9', loan_no: 7, employee: 'زينب علي', amount: 300000, settled_at: '2026-10-28T09:00:00Z' }],
      excluded: [{ loan_no: 8, employee: 'مصطفى حسن', amount: 500000, remaining: 200000, reason: 'عليها باقي 200,000 د.ع.' }],
      requests: [], requests_recent: 1,
      bytes: { settled_rows: 2000, settled_files: 130000, requests_rows: 0, requests_files: 0 },
      archived_total: 3,
    };
    // أول مسير بالقاعدة 2026-09 حتى قائمة التنظيف تبين أيلول (القائمة تبدي من أول مسير — تدقيق 14/10 BUG-017)
    const fixtures = defaultFixtures();
    (fixtures as Record<string, unknown[]>).payroll_periods = [{ period_month: '2026-09' }];
    const api = await mockSupabase(page, { fixtures, rpc: {
      payroll_cleanup_preview: preview, payroll_cleanup_run: { success: true, tracking_deleted: 5400, stops_deleted: 30, violations_deleted: 2 },
      loans_cleanup_preview: loans, loans_cleanup_run: { success: true, loans_archived: 1, loan_requests_deleted: null, pledge_urls: [] },
    } });
    await page.goto('/dashboard/settings');
    await page.getByRole('tab', { name: 'تنظيف البيانات' }).click();
    // الأعداد تبين قبل أي حذف
    await expect(page.getByText('5,432 سجل')).toBeVisible();
    await expect(page.getByText('120 سجل')).toBeVisible();
    // الحضور مقفول لأن المسير اللي بعده بعده مفتوح، مع السبب
    await expect(page.getByRole('switch').first()).toBeDisabled();
    await expect(page.getByText(/لازم تعتمد وتغلق رواتب المسير اللي بعده/)).toBeVisible();
    // المستثنى وسببه: الحركة اللي تنتظر قرار بالاسم
    await expect(page.getByText('مستثنى: حركات تنتظر قرارك (1)')).toBeVisible();
    await expect(page.getByText(/مصطفى حسن · .*خروج مبكر/)).toBeVisible();
    // تقرير المعاينة Excel ينزل من المتصفح فعلاً: ملف xlsx سليم بنفس الشيتات (مكتبة write-excel-file — تدقيق 14/10 CODE-012)
    const download = page.waitForEvent('download');
    await page.getByRole('button', { name: 'تقرير المعاينة Excel' }).click();
    const report = await download;
    expect(report.suggestedFilename()).toMatch(/^معاينة_التنظيف_2026-09_\d{4}-\d{2}-\d{2}\.xlsx$/);
    const xlsx = unzipSync(new Uint8Array(readFileSync(await report.path())));
    const workbook = strFromU8(xlsx['xl/workbook.xml']);
    for (const sheet of ['المسير', 'مستثنى - حركات معلّقة', 'سلف تتأرشف', 'سلف مستثناة', 'طلبات مرفوضة قديمة']) {
      expect(workbook).toContain(`name="${sheet}"`);
    }
    await page.getByRole('switch').nth(1).click();
    // تقدير المساحة للفئة المختارة
    await expect(page.getByText('المساحة التقريبية: 508.8 KB')).toBeVisible();
    await page.getByRole('button', { name: 'تنظيف المحدد' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('5,432 سجل تتبع');
    expect(api.writes('rpc:payroll_cleanup_run', 'POST')).toHaveLength(0);
    await dialog.getByRole('button', { name: 'نعم، حذف نهائي' }).click();
    await expect.poll(() => api.writes('rpc:payroll_cleanup_run', 'POST').length).toBe(1);
    expect(api.writes('rpc:payroll_cleanup_run', 'POST')[0].body).toMatchObject({ p_attendance: false, p_tracking: true, p_notifications: false });

    // تنظيف السلف: المسددة مرشحة للأرشفة، واللي عليها باقي مستثناة مع السبب
    await expect(page.getByText('أرشفة السلف المسددة بالكامل — 1 سلفة')).toBeVisible();
    await expect(page.getByText('L-0007')).toBeVisible();
    await expect(page.getByText('عليها باقي 200,000 د.ع.')).toBeVisible();
    await page.getByRole('switch', { name: /أرشفة السلف المسددة/ }).click();
    await page.getByRole('button', { name: 'تنظيف السلف المحددة' }).click();
    const loansDialog = page.getByRole('dialog');
    await expect(loansDialog).toContainText('أرشفة 1 سلفة مسددة');
    await loansDialog.getByRole('button', { name: 'نعم، نفّذ' }).click();
    await expect.poll(() => api.writes('rpc:loans_cleanup_run', 'POST').length).toBe(1);
    expect(api.writes('rpc:loans_cleanup_run', 'POST')[0].body).toMatchObject({ p_settled: true, p_requests: false });
  });

  test('the employees page opens even if a document list was stored as an object (after the launch reset)', async ({ page }) => {
    const fixtures = defaultFixtures();
    fixtures.employees = fixtures.employees.map((e) => ({ ...e, document_urls: {} }));
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));
    await mockSupabase(page, { fixtures });
    await page.goto('/dashboard/employees');
    await expect(page.getByText('زينب علي').first()).toBeVisible();
    // فتح ملف الموظف (قائمة وثائقه) ثم نموذج التعديل — هنا كانت الصفحة توكف («h.map is not a function»)
    await page.locator('tr', { hasText: 'زينب علي' }).getByRole('button').first().click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.getByText('حدث خطأ غير متوقع')).toHaveCount(0);
    expect(errors).toEqual([]);
  });

  test('ending a service shows how the last salary is computed before anything is saved', async ({ page }) => {
    const summary = (basic: number, note: string) => ({ basic, basic_note: note, earnings: 0, deductions: 0, loans: 0, net: basic });
    const preview = {
      last_day: '2026-10-28', total_net: 853333, loans_left_after: 150000,
      periods: [
        { month: '2026-10', start_date: '2026-10-01', cutoff_date: '2026-10-26', can_approve_now: false, expected_net: 800000, loan_cut: 0, excess_deductions: 0,
          summary: summary(800000, 'راتب المسير كامل: 800,000 د.ع') },
        { month: '2026-11', start_date: '2026-10-27', cutoff_date: '2026-11-26', can_approve_now: false, expected_net: 53333, loan_cut: 0, excess_deductions: 0,
          summary: summary(53333, 'نهاية خدمة: 2 يوم دوام من 27/10 لحد 28/10 (الجمع والعطل الرسمية ما تنحسب) × أجر اليوم 26,667 = 53,333 د.ع') },
      ],
    };
    const api = await mockSupabase(page, { rpc: { end_of_service_preview: preview } });
    await page.goto('/dashboard/employees');
    await page.locator('tr', { hasText: 'زينب علي' }).getByRole('button', { name: 'إنهاء خدمات الموظف' }).click();
    const box = page.getByTestId('end-of-service-preview');
    await expect(box).toContainText('الشهر الحادي عشر 2026');
    await expect(box).toContainText('نهاية خدمة: 2 يوم دوام');
    await expect(box).toContainText('المجموع المستحق: 853,333 د.ع');
    await expect(box).toContainText('تسويها ويا الموظف خارج النظام');
    const call = api.calls.find((c) => c.table === 'rpc:end_of_service_preview');
    expect(call?.body).toMatchObject({ p_last_day: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/) });
    // المعاينة وحدها ما تحفظ شي: لا آخر يوم ولا تعطيل
    expect(api.writes('employees', 'PATCH')).toHaveLength(0);
  });

  test('restoring an employee asks for the return date, and the profile shows his history', async ({ page }) => {
    const fixtures = defaultFixtures();
    fixtures.archived_employees = [{ id: 'ar1', employee_id: 'e9', employee_code: 'EMP-109', full_name: 'حيدر كريم', archived_at: '2026-10-05T09:00:00Z',
      archive_reason: 'استقالة', archive_type: 'archived', scheduled_deletion_date: null }];
    const history = [
      { date: '2026-01-01', kind: 'join', text: 'باشر بالعمل بفرع الكرادة' },
      { date: '2026-09-01', kind: 'transfer', text: 'انتقل من فرع الكرادة إلى فرع المنصور' },
    ];
    const api = await mockSupabase(page, { fixtures, rpc: { restore_archived_employee: { gap_days: 6, warnings: [] }, get_employee_history: history } });
    await page.goto('/dashboard/employees');
    await page.getByRole('tab', { name: /الأرشيف/ }).click();
    await page.getByRole('button', { name: 'تفعيل', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByLabel('تاريخ الرجوع للعمل')).toBeVisible();
    await dialog.getByLabel('تاريخ الرجوع للعمل').fill('2026-10-12');
    await dialog.getByRole('button', { name: 'استعادة' }).click();
    // خطوة وحدة بالسيرفر: التفعيل بتاريخ الرجوع + شيل سجل الأرشيف (تدقيق 14/10 CODE-005)
    await expect.poll(() => api.calls.filter((c) => c.table === 'rpc:restore_archived_employee').length).toBe(1);
    expect(api.calls.find((c) => c.table === 'rpc:restore_archived_employee')?.body).toEqual({ p_archive_id: 'ar1', p_return_date: '2026-10-12' });
    expect(api.writes('archived_employees', 'DELETE')).toHaveLength(0);
    await expect(page.getByText('6 يوم انقطاع ما تنحسب غياب')).toBeVisible();

    await page.getByRole('tab', { name: /دليل الموظفين/ }).click();
    await page.locator('tr', { hasText: 'زينب علي' }).getByRole('button').first().click();
    const historyBox = page.getByTestId('employee-history');
    await expect(historyBox).toContainText('انتقل من فرع الكرادة إلى فرع المنصور');
    await expect(historyBox).toContainText('مباشرة');
  });

  test('editing an employee is one server step, and removed documents are not deleted from the browser', async ({ page }) => {
    const fixtures = defaultFixtures();
    const docUrl = 'https://jgjlmddphhncatrhqrej.supabase.co/storage/v1/object/public/employee-documents/e1/old.jpg';
    fixtures.employees = fixtures.employees.map((e) => (e.id === 'e1' ? { ...e, join_date: '2026-01-01', document_urls: [docUrl] } : e));
    const api = await mockSupabase(page, { fixtures });
    await page.goto('/dashboard/employees');
    await page.locator('tr', { hasText: 'زينب علي' }).getByRole('button', { name: 'تعديل بيانات الموظف' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('الاسم الكامل').fill('زينب علي حسن');
    await dialog.getByRole('button', { name: 'إزالة' }).first().click();
    await dialog.getByRole('button', { name: 'حفظ التعديلات' }).click();
    await expect.poll(() => api.calls.filter((c) => c.table === 'rpc:save_employee').length).toBe(1);
    const body = api.calls.find((c) => c.table === 'rpc:save_employee')?.body as { p_employee_id: string; p_changes: Record<string, unknown> };
    expect(body.p_employee_id).toBe('e1');
    expect(body.p_changes).toMatchObject({ full_name: 'زينب علي حسن', document_urls: [] });
    // المستمسك المشال تحطه القاعدة بالسلة بعد الحفظ؛ المتصفح ما يحذف ملفات ولا يكتب بالجدول مباشرة
    expect(api.calls.filter((c) => c.method === 'DELETE' && c.url.includes('/storage/'))).toHaveLength(0);
    expect(api.writes('employees', 'PATCH')).toHaveLength(0);
    expect(api.calls.filter((c) => c.table === 'rpc:update_employee_credentials')).toHaveLength(0);
  });

  test('archiving (the default end-of-service option) is one server step', async ({ page }) => {
    const api = await mockSupabase(page, { rpc: { end_of_service_preview: { last_day: '2026-10-10', periods: [], total_net: 0, loans_left_after: 0 } } });
    await page.goto('/dashboard/employees');
    await page.locator('tr', { hasText: 'زينب علي' }).getByRole('button', { name: 'إنهاء خدمات الموظف' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'تأكيد وتنفيذ' }).click();
    await expect.poll(() => api.calls.filter((c) => c.table === 'rpc:end_employee_service').length).toBe(1);
    expect(api.calls.find((c) => c.table === 'rpc:end_employee_service')?.body).toMatchObject({ p_employee_id: 'e1', p_type: 'archive' });
    expect(api.writes('employees', 'PATCH')).toHaveLength(0);
    expect(api.writes('archived_employees', 'POST')).toHaveLength(0);
  });

  test('the payroll month list starts at the first real payroll period', async ({ page }) => {
    const fixtures = defaultFixtures();
    const month = new Date().toISOString().slice(0, 7);
    (fixtures as Record<string, unknown[]>).payroll_periods = [{ period_month: month }];
    await mockSupabase(page, { fixtures });
    await page.goto('/dashboard/payroll');
    const select = page.getByLabel('مسير الشهر');
    await expect(select).toBeVisible();
    await expect.poll(async () => (await select.locator('option').evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value)))
      .every((v) => v >= month)).toBe(true);
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
