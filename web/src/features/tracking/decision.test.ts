import { beforeEach, describe, expect, it, vi } from 'vitest';

// Supabase وهمي يسجّل كل استدعاء: from(table) + العمليات، و rpc(name, params)
type Call = { table?: string; rpc?: string; op: string; args: unknown[] };
const calls: Call[] = [];
let payrollEventRow: { id: string } | null = null;
/** سيرفر قديم بدون دالة decide_absence_day */
let oldServer = false;

function builder(table: string) {
  const b: Record<string, (...args: unknown[]) => unknown> = {};
  const chain = (op: string) => (...args: unknown[]) => {
    calls.push({ table, op, args });
    return b;
  };
  for (const op of ['select', 'eq', 'neq', 'order', 'limit', 'update', 'insert']) b[op] = chain(op);
  b.maybeSingle = () => {
    calls.push({ table, op: 'maybeSingle', args: [] });
    return Promise.resolve({ data: table === 'payroll_events' ? payrollEventRow : null, error: null });
  };
  // await على البنّاء نفسه (update/insert بدون maybeSingle)
  b.then = (resolve: unknown) => (resolve as (v: unknown) => void)({ data: null, error: null });
  return b;
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: (table: string) => builder(table),
    rpc: (name: string, params: unknown) => {
      calls.push({ rpc: name, op: 'rpc', args: [params] });
      const missing = oldServer && name === 'decide_absence_day';
      return Promise.resolve({ data: null, error: missing ? { code: 'PGRST202', message: 'function not found' } : null });
    },
  },
}));

import { saveDecision } from './api';

const employee = { id: 'e1', branch_id: 'b1' } as never;

describe('saveDecision — one decision path when a payroll event exists', () => {
  beforeEach(() => {
    calls.length = 0;
    payrollEventRow = null;
    oldServer = false;
  });

  it('uses decide_payroll_event (like the payroll page and the app) and writes nothing else', async () => {
    payrollEventRow = { id: 'pe1' };
    await saveDecision({ employee, type: 'late', date: '2026-10-01', status: 'ignored', recordId: 'a1', reason: 'عذر', fallbackBranchId: null });

    expect(calls.filter((c) => c.rpc)).toEqual([
      { rpc: 'decide_payroll_event', op: 'rpc', args: [{ p_event_id: 'pe1', p_approve: false, p_reason: 'عذر' }] },
    ]);
    // لا تحديث مباشر للحضور ولا إشعار من المتصفح (السيرفر يشعر الموظف) — حتى ما يوصله إشعارين
    expect(calls.some((c) => c.table === 'attendance')).toBe(false);
    expect(calls.some((c) => c.table === 'notifications')).toBe(false);
    // البحث عن الحركة بنفس الموظف واليوم والنوع
    expect(calls.filter((c) => c.table === 'payroll_events' && c.op === 'eq').map((c) => c.args)).toEqual([
      ['employee_id', 'e1'], ['event_date', '2026-10-01'], ['event_type', 'late'],
    ]);
  });

  it('absence without an event (today, not calculated yet): the server records the day and decides, with the edited amount', async () => {
    await saveDecision({ employee, type: 'virtual_absent', date: '2026-10-05', status: 'applied', recordId: null, reason: 'نص يوم', fallbackBranchId: null, amount: 10000 });

    expect(calls.filter((c) => c.rpc)).toEqual([
      { rpc: 'decide_absence_day', op: 'rpc', args: [{ p_employee_id: 'e1', p_date: '2026-10-05', p_approve: true, p_reason: 'نص يوم', p_amount: 10000 }] },
    ]);
    // لا كتابة مباشرة بالحضور ولا إشعار من المتصفح (السيرفر يسويهم)
    expect(calls.some((c) => c.table === 'attendance' && (c.op === 'insert' || c.op === 'update'))).toBe(false);
    expect(calls.some((c) => c.table === 'notifications')).toBe(false);
  });

  it('an edited amount goes with the decision on an existing event; an excuse never sends one', async () => {
    payrollEventRow = { id: 'pe3' };
    await saveDecision({ employee, type: 'late', date: '2026-10-01', status: 'applied', recordId: 'a1', reason: 'x', fallbackBranchId: null, amount: 1000 });
    expect(calls.find((c) => c.rpc)?.args[0]).toEqual({ p_event_id: 'pe3', p_approve: true, p_reason: 'x', p_amount: 1000 });
    calls.length = 0;
    await saveDecision({ employee, type: 'late', date: '2026-10-01', status: 'ignored', recordId: 'a1', reason: 'x', fallbackBranchId: null, amount: 1000 });
    expect(calls.find((c) => c.rpc)?.args[0]).toEqual({ p_event_id: 'pe3', p_approve: false, p_reason: 'x' });
  });

  it('old server without the new function: writes the attendance record and notifies like before', async () => {
    oldServer = true;
    await saveDecision({ employee, type: 'virtual_absent', date: '2026-10-05', status: 'applied', recordId: null, reason: '', fallbackBranchId: null });

    const insert = calls.find((c) => c.table === 'attendance' && c.op === 'insert');
    expect(insert?.args[0]).toMatchObject({ employee_id: 'e1', work_date: '2026-10-05', status: 'absent', deduction_status: 'applied' });
    expect(calls.some((c) => c.table === 'notifications' && c.op === 'insert')).toBe(true);
  });

  it('excuse without an event: saved with its note, and the employee is NOT notified', async () => {
    await saveDecision({ employee, type: 'late', date: '2026-10-05', status: 'ignored', recordId: 'a9', reason: 'نسي البصمة وهو مداوم', fallbackBranchId: null });

    const update = calls.find((c) => c.table === 'attendance' && c.op === 'update');
    expect(update?.args[0]).toMatchObject({ deduction_status: 'ignored', deduction_reason: 'نسي البصمة وهو مداوم' });
    expect(calls.some((c) => c.table === 'notifications')).toBe(false);
  });

  it('excused absence without an event: no notification either', async () => {
    oldServer = true;
    await saveDecision({ employee, type: 'virtual_absent', date: '2026-10-05', status: 'ignored', recordId: null, reason: 'تأخير مبرر', fallbackBranchId: null });
    expect(calls.some((c) => c.table === 'notifications')).toBe(false);
  });

  it('absence decisions look for an "absence" event', async () => {
    payrollEventRow = { id: 'pe2' };
    await saveDecision({ employee, type: 'absent', date: '2026-10-02', status: 'applied', recordId: 'a2', reason: '', fallbackBranchId: null });
    expect(calls.find((c) => c.table === 'payroll_events' && c.op === 'eq' && c.args[0] === 'event_type')?.args[1]).toBe('absence');
    expect(calls.find((c) => c.rpc)?.args[0]).toMatchObject({ p_event_id: 'pe2', p_approve: true });
  });
});
