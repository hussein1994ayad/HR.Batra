// In-browser mock of the Supabase REST/Auth API used by the e2e tests.
// Every request to *.supabase.co is answered from fixtures and recorded so
// tests can assert which writes the UI performed.

import type { Page, Request } from '@playwright/test';

export const PROJECT_REF = 'jgjlmddphhncatrhqrej';
export const ADMIN = { id: 'admin-1', email: 'admin@hrpro.com', password: 'secret123', full_name: 'حسين أياد' };

type Row = Record<string, unknown>;

export interface RecordedCall {
  method: string;
  table: string;
  url: string;
  body: unknown;
}

function localDate(offsetDays = 0): string {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];

export function defaultFixtures(): Record<string, Row[]> {
  const today = localDate();
  const now = new Date().toISOString();
  return {
    employees: [
      { id: ADMIN.id, full_name: ADMIN.full_name, role: 'admin', email: ADMIN.email, is_active: true, branch_id: 'b1', department_id: 'd1', monthly_salary_iqd: 2000000, branches: { name: 'فرع الكرادة' } },
      { id: 'e1', full_name: 'زينب علي', role: 'employee', email: 'zainab@hrpro.com', phone: '07701234567', plain_password: 'Zz123456', is_active: true, branch_id: 'b1', department_id: 'd1', monthly_salary_iqd: 900000, device_id_lock: 'dev-1', branches: { name: 'فرع الكرادة' }, employee_code: 'EMP-101' },
      { id: 'e2', full_name: 'مصطفى حسن', role: 'employee', email: 'mustafa@hrpro.com', is_active: true, branch_id: 'b2', department_id: 'd1', monthly_salary_iqd: 750000, branches: { name: 'فرع المنصور' }, employee_code: 'EMP-102' },
    ],
    branches: [
      { id: 'b1', name: 'فرع الكرادة', latitude: 33.3, longitude: 44.42, radius_meters: 150, address: 'بغداد - الكرادة', created_at: now },
      { id: 'b2', name: 'فرع المنصور', latitude: 33.32, longitude: 44.35, radius_meters: 200, address: 'بغداد - المنصور', created_at: now },
    ],
    departments: [{ id: 'd1', name: 'المبيعات' }],
    // A 7-day schedule keeps absence logic deterministic whatever weekday the tests run on.
    work_schedules: [{ id: 's1', name: 'دوام كامل', branch_id: 'b1', department_id: null, employee_id: null, check_in_time: '09:00:00', check_out_time: '17:00:00', grace_period_minutes: 15, work_days: ALL_DAYS }, { id: 's2', name: 'دوام المنصور', branch_id: 'b2', department_id: null, employee_id: null, check_in_time: '09:00:00', check_out_time: '17:00:00', grace_period_minutes: 15, work_days: ALL_DAYS }],
    attendance: [
      { id: 'att1', employee_id: 'e1', branch_id: 'b1', work_date: today, status: 'present', check_in_time: now, check_in_lat: 33.3001, check_in_lng: 44.4201, employees: { full_name: 'زينب علي', branch_id: 'b1' } },
    ],
    leave_requests: [
      { id: 'lv1', employee_id: 'e2', start_date: localDate(3), end_date: localDate(5), leave_type: 'annual', is_paid: true, status: 'pending', reason: 'سفر عائلي', created_at: now, employees: { full_name: 'مصطفى حسن' } },
    ],
    loans: [
      { id: 'ln1', employee_id: 'e2', amount: 600000, installment_amount: 100000, installment_count: 6, remaining_amount: 600000, status: 'pending', pledge_url: 'https://example.com/p.pdf', created_at: now, employees: { full_name: 'مصطفى حسن' } },
      { id: 'ln2', employee_id: 'e1', amount: 300000, installment_amount: 100000, installment_count: 3, remaining_amount: 200000, status: 'approved', created_at: now, employees: { full_name: 'زينب علي' }, loan_installments: [{ id: 'i1', loan_id: 'ln2', due_date: localDate(-20), amount: 100000, is_paid: true, payment_type: 'salary_deduction' }, { id: 'i2', loan_id: 'ln2', due_date: localDate(10), amount: 100000, is_paid: false }] },
    ],
    loan_installments: [{ id: 'i2', loan_id: 'ln2', due_date: localDate(10), amount: 100000, is_paid: false, loans: { employee_id: 'e1' } }],
    bonuses_deductions: [
      { id: 'bd1', employee_id: 'e1', type: 'bonus', amount: 50000, reason: 'مكافأة أداء', issue_date: today },
      { id: 'bd2', employee_id: 'e1', type: 'deduction', amount: 20000, reason: 'خصم إداري', issue_date: today },
    ],
    salary_slips: [],
    employee_devices: [{ id: 'dv1', employee_id: 'e2', device_id: 'dev-2', device_model: 'Galaxy S24', os_version: 'Android 15', is_approved: false, employees: { full_name: 'مصطفى حسن' } }],
    mock_gps_attempts: [{ id: 'm1', employee_id: 'e2', latitude: 33.31, longitude: 44.36, app_used: 'Fake GPS', timestamp: now, employees: { full_name: 'مصطفى حسن' } }],
    geofence_violations: [],
    geofence_zones: [],
    notifications: [{ id: 'n1', employee_id: ADMIN.id, title: 'طلب جديد', body: 'قدّم موظف طلب إجازة', type: 'leave', is_read: false, created_at: now }],
    deleted_files: [{ id: 'f1', file_path: 'e1/old-id.jpg', file_type: 'document', deleted_at: now, scheduled_deletion_date: new Date(Date.now() + 20 * 86400000).toISOString(), file_size_bytes: 204800, employees: { full_name: ADMIN.full_name } }],
    archived_employees: [],
    announcements: [{ id: 'an1', title: 'تعميم إداري هام 📢', content: 'الدوام يبدأ الساعة 9', is_pinned: false, created_at: now }],
    company_settings: [{ id: 'c1', name: 'شركة بترا', address: 'بغداد', phone: '+964770', email: 'info@batra.iq' }],
    system_settings: [],
    location_tracking: [],
  };
}

export function sessionFor(user = ADMIN) {
  const now = Math.floor(Date.now() / 1000);
  return {
    access_token: 'e2e.access.token',
    refresh_token: 'e2e-refresh',
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: now + 3600,
    user: { id: user.id, email: user.email, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} },
  };
}

function tableOf(url: URL): string {
  const parts = url.pathname.split('/rest/v1/')[1] ?? '';
  return parts.split('?')[0];
}

/** Applies simple `col=eq.value` / `col=is.null` filters so pages get plausible subsets. */
function applyFilters(rows: Row[], url: URL): Row[] {
  let out = rows;
  url.searchParams.forEach((value, key) => {
    if (['select', 'order', 'limit', 'offset', 'or', 'on_conflict', 'columns'].includes(key)) return;
    const [op, ...rest] = value.split('.');
    const arg = rest.join('.');
    if (op === 'eq') out = out.filter((r) => String(r[key]) === arg);
    else if (op === 'is' && arg === 'null') out = out.filter((r) => r[key] == null);
    else if (op === 'in') {
      const set = arg.replace(/^\(|\)$/g, '').split(',');
      out = out.filter((r) => set.includes(String(r[key])));
    }
  });
  return out;
}

export interface MockOptions {
  fixtures?: Record<string, Row[]>;
  loggedIn?: boolean;
  rpc?: Record<string, unknown>;
}

export async function mockSupabase(page: Page, options: MockOptions = {}) {
  const fixtures = options.fixtures ?? defaultFixtures();
  const calls: RecordedCall[] = [];
  const rpc = { get_storage_stats: [{ bucket_name: 'employee-documents', total_size: 52428800 }], perform_daily_cleanup: null, ...options.rpc };

  if (options.loggedIn !== false) {
    const session = sessionFor();
    await page.addInitScript(
      ([key, value]) => {
        window.localStorage.setItem(key, value);
      },
      [`sb-${PROJECT_REF}-auth-token`, JSON.stringify(session)],
    );
  }

  await page.route(/supabase\.co\//, async (route) => {
    const req: Request = route.request();
    const url = new URL(req.url());
    const method = req.method();
    const cors = { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range' };

    if (url.pathname.startsWith('/auth/v1/')) {
      if (url.pathname.endsWith('/token')) {
        const body = req.postDataJSON() as { email?: string; password?: string } | null;
        if (body?.email === ADMIN.email && body?.password === ADMIN.password) {
          return route.fulfill({ status: 200, headers: cors, json: sessionFor() });
        }
        return route.fulfill({ status: 400, headers: cors, json: { error: 'invalid_grant', error_description: 'Invalid login credentials' } });
      }
      if (url.pathname.endsWith('/logout')) return route.fulfill({ status: 204, headers: cors, body: '' });
      return route.fulfill({ status: 200, headers: cors, json: sessionFor().user });
    }

    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      const name = url.pathname.split('/rpc/')[1];
      calls.push({ method, table: `rpc:${name}`, url: req.url(), body: req.postDataJSON() });
      return route.fulfill({ status: 200, headers: cors, json: rpc[name as keyof typeof rpc] ?? null });
    }

    if (url.pathname.startsWith('/realtime/')) return route.abort();

    const table = tableOf(url);
    if (method !== 'GET' && method !== 'HEAD') {
      let body: unknown = null;
      try {
        body = req.postDataJSON();
      } catch {
        body = req.postData();
      }
      calls.push({ method, table, url: req.url(), body });
      return route.fulfill({ status: method === 'POST' ? 201 : 204, headers: cors, body: '' });
    }

    const rows = applyFilters(fixtures[table] ?? [], url);
    const range = { 'content-range': `0-${Math.max(rows.length - 1, 0)}/${rows.length}` };
    if (method === 'HEAD') return route.fulfill({ status: 200, headers: { ...cors, ...range }, body: '' });

    const wantsObject = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object');
    if (wantsObject) {
      if (rows.length === 0) return route.fulfill({ status: 406, headers: cors, json: { code: 'PGRST116', message: 'no rows' } });
      return route.fulfill({ status: 200, headers: { ...cors, ...range }, json: rows[0] });
    }
    return route.fulfill({ status: 200, headers: { ...cors, ...range }, json: rows });
  });

  return {
    calls,
    writes: (table: string, method?: string) => calls.filter((c) => c.table === table && (!method || c.method === method)),
  };
}
