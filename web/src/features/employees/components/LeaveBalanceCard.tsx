'use client';

// رصيد إجازات الموظف (السنة الحالية + زمنيات الشهر الحالي) مع تخصيص الرصيد.
// الحقل الفارغ في التخصيص = حسب سياسة الإجازات في الإعدادات.

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { CalendarRange, Save, SlidersHorizontal } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { useQuery } from '@/lib/useQuery';
import { errorMessage } from '@/lib/format';
import { Button, Field, Input } from '@/components/ui';

type Part = { entitlement: number; used: number; pending: number; left: number };
type Balance = {
  year: number;
  month: string;
  annual: Part;
  sick: Part;
  hourly: { allowance_hours: number; used_hours: number; pending_hours: number; left_hours: number };
};
type Overrides = { annual: string; sick: string; hours: string };

const num = (v: number | string) => {
  const n = Number(v);
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
};

function Tile({ label, left, total, unit, note }: { label: string; left: number; total: number; unit: string; note?: string }) {
  return (
    <div className="rounded-xl bg-slate-900/50 border border-slate-800/80 p-3">
      <p className="text-[10px] text-slate-500 mb-1">{label}</p>
      <p className="text-sm font-extrabold text-white">
        {num(left)} <span className="text-[11px] font-bold text-slate-400">من {num(total)} {unit}</span>
      </p>
      {note && <p className="text-[10px] text-amber-300/80 mt-0.5">{note}</p>}
    </div>
  );
}

export function LeaveBalanceCard({ employeeId }: { employeeId: string }) {
  const [editing, setEditing] = useState<Overrides | null>(null);
  const [saving, setSaving] = useState(false);

  const query = useQuery(`leave-balance:${employeeId}`, async () => {
    const { data, error } = await supabase.rpc('get_leave_balance', { p_employee_id: employeeId });
    if (error) throw error;
    return data as Balance;
  });
  const balance = query.data ?? null;

  const startEdit = async () => {
    const { data } = await supabase
      .from('leave_balances')
      .select('annual_entitlement, sick_entitlement, hourly_monthly_hours')
      .eq('employee_id', employeeId)
      .maybeSingle();
    setEditing({
      annual: data?.annual_entitlement?.toString() ?? '',
      sick: data?.sick_entitlement?.toString() ?? '',
      hours: data?.hourly_monthly_hours?.toString() ?? '',
    });
  };

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editing) return;
    const val = (s: string) => (s.trim() === '' ? null : Number(s));
    setSaving(true);
    const { error } = await supabase.rpc('set_employee_leave_entitlement', {
      p_employee_id: employeeId,
      p_annual: val(editing.annual),
      p_sick: val(editing.sick),
      p_hourly_monthly_hours: val(editing.hours),
    });
    setSaving(false);
    if (error) return void toast.error(`فشل حفظ الرصيد: ${errorMessage(error)}`);
    toast.success('تم حفظ رصيد الموظف');
    setEditing(null);
    query.reload();
  };

  const pendingNote = (p: number, unit: string) => (p > 0 ? `منها ${num(p)} ${unit} بانتظار الموافقة` : undefined);

  return (
    <div className="mb-6">
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-sm font-bold text-white flex items-center gap-2">
          <CalendarRange className="w-4 h-4 text-amber-300" /> رصيد الإجازات {balance && <span className="text-[11px] text-slate-500">({balance.year})</span>}
        </h4>
        {!editing && (
          <Button size="xs" variant="secondary" icon={SlidersHorizontal} onClick={startEdit}>
            تخصيص رصيد الموظف
          </Button>
        )}
      </div>

      {balance ? (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <Tile label="الإجازة السنوية المتبقية" left={balance.annual.left} total={balance.annual.entitlement} unit="يوم" note={pendingNote(balance.annual.pending, 'يوم')} />
          <Tile label="الإجازة المرضية المتبقية" left={balance.sick.left} total={balance.sick.entitlement} unit="يوم" note={pendingNote(balance.sick.pending, 'يوم')} />
          <Tile
            label={`الزمنيات المتبقية (${balance.month})`}
            left={balance.hourly.left_hours}
            total={balance.hourly.allowance_hours}
            unit="ساعة"
            note={pendingNote(balance.hourly.pending_hours, 'ساعة')}
          />
        </div>
      ) : (
        <p className="text-xs text-slate-500">جارٍ تحميل الرصيد…</p>
      )}

      {editing && (
        <form onSubmit={save} className="mt-3 rounded-2xl border border-slate-800/80 bg-slate-950/40 p-3">
          <p className="text-[11px] text-slate-400 mb-3">اترك الحقل فارغاً ليتبع سياسة الإجازات العامة في الإعدادات.</p>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Field label="السنوية (يوم/سنة)">
              <Input type="number" min={0} step={0.5} value={editing.annual} onChange={(e) => setEditing({ ...editing, annual: e.target.value })} placeholder="حسب السياسة" dir="ltr" className="text-left" />
            </Field>
            <Field label="المرضية (يوم/سنة)">
              <Input type="number" min={0} step={0.5} value={editing.sick} onChange={(e) => setEditing({ ...editing, sick: e.target.value })} placeholder="حسب السياسة" dir="ltr" className="text-left" />
            </Field>
            <Field label="الزمنيات (ساعة/شهر)">
              <Input type="number" min={0} step={0.5} value={editing.hours} onChange={(e) => setEditing({ ...editing, hours: e.target.value })} placeholder="حسب السياسة" dir="ltr" className="text-left" />
            </Field>
          </div>
          <div className="flex justify-end gap-2 mt-3">
            <Button size="sm" variant="secondary" onClick={() => setEditing(null)}>
              إلغاء
            </Button>
            <Button size="sm" type="submit" icon={Save} loading={saving}>
              حفظ
            </Button>
          </div>
        </form>
      )}
    </div>
  );
}
