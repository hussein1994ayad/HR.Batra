'use client';

import React, { useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import {
  Coins,
  X,
  Calendar,
  Settings2,
  CreditCard,
  Save,
  FileText,
  Wallet,
  CalendarClock,
  Pencil,
  Undo2,
  Trash2,
  Banknote,
  CheckCircle2,
  Hourglass,
  AlertTriangle,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { errorMessage, formatIQD, localDateStr } from '@/lib/format';
import type { Loan, LoanInstallment } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import {
  AmountInput,
  Avatar,
  Badge,
  Button,
  Card,
  CardHeader,
  DataTable,
  EmptyState,
  Field,
  IconButton,
  Input,
  Modal,
  ModalFooter,
  PageHeader,
  PageSkeleton,
  SearchInput,
  SegmentedTabs,
  StatTile,
  TableEmpty,
} from '@/components/ui';

interface LoansData {
  pending: Loan[];
  approved: Loan[];
}

async function fetchLoans(): Promise<LoansData> {
  const [{ data: pending, error: pErr }, { data: approved, error: aErr }] = await Promise.all([
    supabase
      .from('loans')
      .select('*, employees!loans_employee_id_fkey(full_name)')
      .eq('status', 'pending')
      .order('created_at', { ascending: false }),
    supabase
      .from('loans')
      .select('*, employees!loans_employee_id_fkey(full_name), loan_installments(*)')
      .eq('status', 'approved')
      .order('created_at', { ascending: false }),
  ]);
  if (pErr) throw pErr;
  if (aErr) throw aErr;
  return { pending: (pending ?? []) as Loan[], approved: (approved ?? []) as Loan[] };
}

const byDueDate = (a: LoanInstallment, b: LoanInstallment) => a.due_date.localeCompare(b.due_date);

function addMonths(dateStr: string, months: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  return localDateStr(new Date(y, m - 1 + months, d));
}

interface ApprovalDraft {
  loan: Loan;
  amount: number;
  months: number;
  startDate: string;
}

interface EditDraft {
  loan: Loan;
  amount: number;
  installmentAmount: number;
  installmentCount: number;
  remainingAmount: number;
}

export default function LoansPage() {
  const confirm = useConfirm();
  const query = useQuery('loans', fetchLoans);
  const [tab, setTab] = useState<'active' | 'completed'>('active');
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const [approval, setApproval] = useState<ApprovalDraft | null>(null);
  const [editDraft, setEditDraft] = useState<EditDraft | null>(null);
  const [scheduleLoanId, setScheduleLoanId] = useState<string | null>(null);
  const [cashPrompt, setCashPrompt] = useState<{ installment: LoanInstallment; note: string } | null>(null);
  const [amountPrompt, setAmountPrompt] = useState<{ installment: LoanInstallment; amount: number } | null>(null);

  const approved = useMemo(() => query.data?.approved ?? [], [query.data]);
  const active = approved.filter((l) => Number(l.remaining_amount) > 0);
  const completed = approved.filter((l) => Number(l.remaining_amount) <= 0);
  const outstanding = active.reduce((sum, l) => sum + Number(l.remaining_amount), 0);
  const scheduleLoan = approved.find((l) => l.id === scheduleLoanId) ?? null;

  const displayed = (tab === 'active' ? active : completed).filter((l) =>
    (l.employees?.full_name || '').toLowerCase().includes(search.trim().toLowerCase()),
  );

  if (!query.data) {
    if (query.error) {
      return (
        <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل السلف" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />
      );
    }
    return <PageSkeleton />;
  }
  const pending = query.data.pending;

  const run = async (key: string, action: () => Promise<void>, failMsg: string) => {
    setBusy(key);
    try {
      await action();
    } catch (err) {
      toast.error(`${failMsg}: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const startApproval = (loan: Loan) =>
    setApproval({
      loan,
      amount: Number(loan.amount),
      months: Number(loan.installment_count),
      startDate: addMonths(localDateStr(), 1),
    });

  const rejectLoan = async (loan: Loan) => {
    const ok = await confirm({ title: 'رفض طلب السلفة؟', message: `سيتم إشعار ${loan.employees?.full_name || 'الموظف'} برفض الطلب.`, confirmLabel: 'رفض الطلب' });
    if (!ok) return;
    await run(
      loan.id,
      async () => {
        const {
          data: { session },
        } = await supabase.auth.getSession();
        if (!session) return;
        const { error } = await supabase
          .from('loans')
          .update({ status: 'rejected', approved_by: session.user.id, approved_at: new Date().toISOString() })
          .eq('id', loan.id);
        if (error) throw error;
        await supabase.from('notifications').insert({
          employee_id: loan.employee_id,
          title: 'رفض طلب السلفة ❌',
          body: 'نأسف، تم رفض طلب السلفة المقدم من قبلك.',
          type: 'loan',
        });
        query.mutate((d) => ({ ...d, pending: d.pending.filter((l) => l.id !== loan.id) }));
        toast.success('تم رفض طلب السلفة');
      },
      'فشل معالجة الطلب',
    );
  };

  const submitApproval = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!approval || approval.months <= 0) return;
    await run(
      'approve',
      async () => {
        const {
          data: { session },
        } = await supabase.auth.getSession();
        if (!session) return;
        const installmentAmt = Math.round(approval.amount / approval.months);
        const { error } = await supabase
          .from('loans')
          .update({
            status: 'approved',
            amount: approval.amount,
            installment_count: approval.months,
            installment_amount: installmentAmt,
            approved_by: session.user.id,
            approved_at: new Date().toISOString(),
          })
          .eq('id', approval.loan.id);
        if (error) throw error;

        const installments = Array.from({ length: approval.months }, (_, i) => ({
          loan_id: approval.loan.id,
          due_date: addMonths(approval.startDate, i),
          amount: installmentAmt,
          is_paid: false,
        }));
        const { error: instErr } = await supabase.from('loan_installments').insert(installments);
        if (instErr) throw instErr;

        await supabase.from('notifications').insert({
          employee_id: approval.loan.employee_id,
          title: 'الموافقة على طلب السلفة 💸',
          body: `تم اعتماد سلفة بقيمة ${approval.amount.toLocaleString()} د.ع وجدولتها على ${approval.months} شهر.`,
          type: 'loan',
        });

        setApproval(null);
        query.reload();
        confetti({ particleCount: 100, spread: 70, colors: ['#818CF8', '#34D399', '#6EE7B7'] });
        toast.success('تم اعتماد السلفة وتوليد الأقساط');
      },
      'فشل الاعتماد',
    );
  };

  const submitEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editDraft) return;
    const d = editDraft;
    await run(
      'edit',
      async () => {
        const { error } = await supabase
          .from('loans')
          .update({
            amount: Math.round(d.amount),
            installment_amount: Math.round(d.installmentAmount),
            installment_count: d.installmentCount,
            remaining_amount: Math.round(d.remainingAmount),
          })
          .eq('id', d.loan.id);
        if (error) throw error;

        // Regenerate the unpaid installments starting next month.
        const { data: paidInst } = await supabase.from('loan_installments').select('id').eq('loan_id', d.loan.id).eq('is_paid', true);
        const { error: delErr } = await supabase.from('loan_installments').delete().eq('loan_id', d.loan.id).eq('is_paid', false);
        if (delErr) throw delErr;

        const remainingCount = d.installmentCount - (paidInst?.length ?? 0);
        if (remainingCount > 0) {
          const now = new Date();
          const first = localDateStr(new Date(now.getFullYear(), now.getMonth() + 1, 1));
          const { error: instErr } = await supabase.from('loan_installments').insert(
            Array.from({ length: remainingCount }, (_, i) => ({
              loan_id: d.loan.id,
              due_date: addMonths(first, i),
              amount: Math.round(d.installmentAmount),
              is_paid: false,
            })),
          );
          if (instErr) throw instErr;
        }

        await supabase.from('notifications').insert({
          employee_id: d.loan.employee_id,
          title: 'تعديل تفاصيل السلفة 💸',
          body: `قامت الإدارة بتعديل تفاصيل سلفتك (المبلغ الكلي الجديد: ${Math.round(d.amount).toLocaleString()} د.ع، القسط الشهري الجديد: ${Math.round(d.installmentAmount).toLocaleString()} د.ع).`,
          type: 'loan',
        });

        setEditDraft(null);
        query.reload();
        toast.success('تم تعديل السلفة وإعادة جدولة الأقساط المتبقية');
      },
      'فشل التعديل',
    );
  };

  const recordCash = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!cashPrompt) return;
    await run(
      'cash',
      async () => {
        const { error } = await supabase
          .from('loan_installments')
          .update({
            is_paid: true,
            paid_at: new Date().toISOString(),
            payment_type: 'cash',
            payment_note: cashPrompt.note || 'سداد نقدي مباشر',
          })
          .eq('id', cashPrompt.installment.id);
        if (error) throw error;
        setCashPrompt(null);
        query.reload();
        toast.success('تم تسجيل السداد النقدي وتحديث الرصيد');
      },
      'فشل تسجيل السداد',
    );
  };

  const updateInstallmentAmount = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amountPrompt || amountPrompt.amount <= 0) return;
    await run(
      'amount',
      async () => {
        const { error } = await supabase.from('loan_installments').update({ amount: amountPrompt.amount }).eq('id', amountPrompt.installment.id);
        if (error) throw error;
        setAmountPrompt(null);
        query.reload();
        toast.success('تم تعديل قيمة القسط');
      },
      'فشل تعديل القسط',
    );
  };

  const revertPayment = async (inst: LoanInstallment) => {
    const ok = await confirm({
      title: 'التراجع عن السداد؟',
      message: 'سيعود القسط غير مدفوع ويُضاف للمبلغ المتبقي ليُستقطع مع الراتب القادم.',
      confirmLabel: 'تراجع عن السداد',
      tone: 'warning',
    });
    if (!ok) return;
    await run(
      `revert_${inst.id}`,
      async () => {
        const { error } = await supabase
          .from('loan_installments')
          .update({ is_paid: false, paid_at: null, payment_type: 'salary_deduction', payment_note: null })
          .eq('id', inst.id);
        if (error) throw error;
        query.reload();
        toast.success('تم التراجع عن السداد');
      },
      'فشل التراجع عن السداد',
    );
  };

  const deletePaidInstallment = async (inst: LoanInstallment) => {
    const ok = await confirm({
      title: 'حذف القسط المسدد نهائياً؟',
      message: 'يُحذف السجل من قاعدة البيانات لتوفير المساحة، ولن يؤثر على رصيد السلفة المتبقي. لا يمكن التراجع.',
      confirmLabel: 'حذف نهائي',
    });
    if (!ok) return;
    await run(
      `delete_${inst.id}`,
      async () => {
        const { error } = await supabase.from('loan_installments').delete().eq('id', inst.id);
        if (error) throw error;
        query.mutate((d) => ({
          ...d,
          approved: d.approved.map((l) =>
            l.id === inst.loan_id ? { ...l, loan_installments: (l.loan_installments ?? []).filter((i) => i.id !== inst.id) } : l,
          ),
        }));
        toast.success('تم حذف القسط المسدد');
      },
      'فشل حذف القسط',
    );
  };

  const postponeFrom = async (inst: LoanInstallment) => {
    await run(
      `postpone_${inst.id}`,
      async () => {
        const { data: later, error } = await supabase
          .from('loan_installments')
          .select('*')
          .eq('loan_id', inst.loan_id)
          .eq('is_paid', false)
          .gte('due_date', inst.due_date)
          .order('due_date', { ascending: true });
        if (error) throw error;
        for (const item of (later ?? []) as LoanInstallment[]) {
          await supabase.from('loan_installments').update({ due_date: addMonths(item.due_date, 1) }).eq('id', item.id);
        }
        query.reload();
        toast.success('تم تأجيل القسط والأقساط اللاحقة شهراً');
      },
      'فشل تأجيل القسط',
    );
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader icon={Coins} tone="sky" title="السلف والأقساط" description="اعتماد طلبات السلف وجدولة الأقساط الشهرية ومتابعة السداد" />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="طلبات معلقة" value={pending.length} icon={Hourglass} tone={pending.length > 0 ? 'amber' : 'slate'} />
        <StatTile label="سلف جارية" value={active.length} icon={CreditCard} tone="sky" />
        <StatTile label="المبالغ المتبقية" value={formatIQD(outstanding)} icon={Wallet} tone="indigo" />
        <StatTile label="سلف مكتملة" value={completed.length} icon={CheckCircle2} tone="emerald" />
      </div>

      {/* Pending requests */}
      <Card>
        <CardHeader
          icon={Hourglass}
          tone="amber"
          title={<>طلبات بانتظار الاعتماد {pending.length > 0 && <Badge tone="amber">{pending.length}</Badge>}</>}
          description="راجع الطلب ثم اعتمده مع إمكانية تعديل المبلغ ومدة التقسيط"
        />
        {pending.length === 0 ? (
          <EmptyState icon={Coins} title="لا توجد طلبات سلف معلقة" description="ستظهر هنا الطلبات الجديدة فور رفعها من تطبيق الموظفين." />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {pending.map((loan) => {
              const amount = Number(loan.amount);
              const months = Number(loan.installment_count) || 1;
              return (
                <article key={loan.id} className="flex flex-col rounded-2xl bg-slate-900/50 border border-slate-800/80 hover:border-slate-700/80 transition-colors p-5">
                  <div className="flex items-center gap-3 mb-4">
                    <Avatar name={loan.employees?.full_name} />
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-bold text-white truncate">{loan.employees?.full_name || 'موظف'}</h4>
                      <p className="text-[11px] text-slate-500">طلب سلفة مالية</p>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-2 mb-3">
                    <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                      <p className="text-[10px] text-slate-500 mb-0.5">المبلغ</p>
                      <p className="text-sm font-extrabold text-white">{formatIQD(amount)}</p>
                    </div>
                    <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                      <p className="text-[10px] text-slate-500 mb-0.5">المدة</p>
                      <p className="text-sm font-extrabold text-white">{months} شهر</p>
                    </div>
                  </div>
                  <div className="flex items-center justify-between rounded-xl bg-sky-500/5 border border-sky-500/15 px-3 py-2.5 mb-3">
                    <span className="text-xs text-slate-400">القسط الشهري</span>
                    <span className="text-sm font-extrabold text-sky-300">{formatIQD(amount / months)}</span>
                  </div>
                  {loan.pledge_url && (
                    <a href={loan.pledge_url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 text-xs font-bold text-indigo-300 hover:text-indigo-200 mb-3">
                      <FileText className="w-3.5 h-3.5" /> عرض التعهد الموقّع
                    </a>
                  )}
                  <div className="flex gap-2 mt-auto pt-4 border-t border-slate-800/70">
                    <Button variant="primary" icon={Settings2} block disabled={busy === loan.id} onClick={() => startApproval(loan)}>
                      اعتماد وجدولة
                    </Button>
                    <Button variant="soft-danger" icon={X} block loading={busy === loan.id} onClick={() => rejectLoan(loan)}>
                      رفض
                    </Button>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </Card>

      {/* Active & completed loans */}
      <Card>
        <CardHeader
          icon={CreditCard}
          tone="indigo"
          title="سجل السلف المعتمدة"
          description="اضغط على جدول الأقساط لتسجيل سداد نقدي أو تأجيل أو تعديل قسط"
          actions={
            <>
              <SearchInput value={search} onChange={setSearch} placeholder="ابحث باسم الموظف..." className="w-full sm:w-56" />
              <SegmentedTabs
                value={tab}
                onChange={setTab}
                options={[
                  { value: 'active', label: 'الجارية', count: active.length },
                  { value: 'completed', label: 'المكتملة', count: completed.length },
                ]}
              />
            </>
          }
        />
        <DataTable>
          <thead>
            <tr>
              <th>الموظف</th>
              <th>المبلغ الكلي</th>
              <th>نسبة السداد</th>
              <th>المتبقي</th>
              <th>القسط القادم</th>
              <th className="!text-left">الإجراءات</th>
            </tr>
          </thead>
          <tbody>
            {displayed.length === 0 ? (
              <TableEmpty colSpan={6}>{tab === 'active' ? 'لا توجد سلف جارية' : 'لا توجد سلف مكتملة'}</TableEmpty>
            ) : (
              displayed.map((loan) => {
                const unpaid = (loan.loan_installments ?? []).filter((i) => !i.is_paid).sort(byDueDate);
                const amount = Number(loan.amount);
                const paidPct = amount > 0 ? Math.min(100, Math.max(0, Math.round(((amount - Number(loan.remaining_amount)) / amount) * 100))) : 0;
                return (
                  <tr key={loan.id}>
                    <td>
                      <div className="flex items-center gap-2.5">
                        <Avatar name={loan.employees?.full_name} size="sm" />
                        <span className="font-bold text-white">{loan.employees?.full_name}</span>
                      </div>
                    </td>
                    <td className="font-bold text-slate-200">{formatIQD(amount)}</td>
                    <td className="min-w-[140px]">
                      <div className="flex items-center gap-2">
                        <div className="flex-1 h-1.5 rounded-full bg-slate-800 overflow-hidden" dir="ltr">
                          <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-teal-400" style={{ width: `${paidPct}%` }} />
                        </div>
                        <span className="text-[11px] font-bold text-slate-400 w-9" dir="ltr">{paidPct}%</span>
                      </div>
                    </td>
                    <td>
                      <span className={Number(loan.remaining_amount) > 0 ? 'font-bold text-amber-300' : 'font-bold text-emerald-300'}>
                        {formatIQD(loan.remaining_amount)}
                      </span>
                      <span className="block text-[10px] text-slate-500">{unpaid.length} أقساط متبقية</span>
                    </td>
                    <td className="font-mono text-slate-300" dir="ltr">
                      {unpaid[0]?.due_date ?? <Badge tone="emerald">مكتمل</Badge>}
                    </td>
                    <td className="!text-left">
                      <Button size="sm" variant="soft" icon={Calendar} onClick={() => setScheduleLoanId(loan.id)}>
                        جدول الأقساط
                      </Button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </DataTable>
      </Card>

      {/* Approval */}
      {approval && (
        <Modal title="اعتماد وجدولة السلفة" subtitle={approval.loan.employees?.full_name ?? undefined} icon={Settings2} tone="brand" onClose={() => setApproval(null)}>
          <form onSubmit={submitApproval} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <Field label="المبلغ الإجمالي (د.ع)">
                <AmountInput required value={approval.amount} onValueChange={(v) => setApproval({ ...approval, amount: v })} />
              </Field>
              <Field label="عدد أشهر التقسيط">
                <AmountInput required value={approval.months} onValueChange={(v) => setApproval({ ...approval, months: v })} />
              </Field>
            </div>
            <Field label="تاريخ استحقاق أول قسط">
              <Input type="date" required value={approval.startDate} onChange={(e) => setApproval({ ...approval, startDate: e.target.value })} dir="ltr" />
            </Field>
            <div className="rounded-2xl bg-indigo-500/5 border border-indigo-500/20 p-4 text-center">
              <p className="text-[11px] text-slate-400 mb-1">القسط الشهري</p>
              <p className="text-2xl font-extrabold text-indigo-200">{formatIQD(approval.months > 0 ? approval.amount / approval.months : 0)}</p>
            </div>
            <ModalFooter onCancel={() => setApproval(null)} loading={busy === 'approve'} submitLabel="حفظ وتوليد الأقساط" submitIcon={Save} />
          </form>
        </Modal>
      )}

      {/* Installment schedule */}
      {scheduleLoan && (
        <Modal
          title="جدول الأقساط والسداد"
          subtitle={scheduleLoan.employees?.full_name ?? undefined}
          icon={Calendar}
          tone="sky"
          size="lg"
          onClose={() => setScheduleLoanId(null)}
        >
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
            <StatTile label="المبلغ الكلي" value={formatIQD(scheduleLoan.amount)} tone="slate" className="!p-3" />
            <StatTile label="المسدد" value={formatIQD(Number(scheduleLoan.amount) - Number(scheduleLoan.remaining_amount))} tone="emerald" className="!p-3" />
            <StatTile label="المتبقي" value={formatIQD(scheduleLoan.remaining_amount)} tone="amber" className="!p-3" />
            <StatTile label="القسط الشهري" value={formatIQD(scheduleLoan.installment_amount)} tone="indigo" className="!p-3" />
          </div>

          <div className="flex items-center justify-between mb-3">
            <h4 className="text-xs font-bold text-slate-300">الأقساط</h4>
            <Button
              size="sm"
              variant="secondary"
              icon={Pencil}
              onClick={() =>
                setEditDraft({
                  loan: scheduleLoan,
                  amount: Number(scheduleLoan.amount),
                  installmentAmount: Number(scheduleLoan.installment_amount),
                  installmentCount: Number(scheduleLoan.installment_count),
                  remainingAmount: Number(scheduleLoan.remaining_amount),
                })
              }
            >
              تعديل السلفة وإعادة الجدولة
            </Button>
          </div>

          <div className="max-h-[360px] overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
            {[...(scheduleLoan.loan_installments ?? [])].sort(byDueDate).map((inst, idx) => (
              <div key={inst.id} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-slate-900/40 transition-colors">
                <div className="flex items-center gap-3 text-xs">
                  <span className="w-7 h-7 shrink-0 rounded-lg bg-slate-800 text-slate-400 font-bold flex items-center justify-center text-[11px]">{idx + 1}</span>
                  <span className="font-mono text-slate-300" dir="ltr">{inst.due_date}</span>
                  <span className="font-bold text-white">{formatIQD(inst.amount)}</span>
                  {inst.is_paid ? (
                    <Badge tone={inst.payment_type === 'cash' ? 'emerald' : 'sky'} dot>
                      {inst.payment_type === 'cash' ? `نقداً${inst.payment_note ? ` · ${inst.payment_note}` : ''}` : 'استقطاع راتب'}
                    </Badge>
                  ) : (
                    <Badge tone="slate">غير مدفوع</Badge>
                  )}
                </div>
                <div className="flex items-center gap-1.5 justify-end">
                  {!inst.is_paid ? (
                    <>
                      <Button size="xs" variant="soft-success" icon={Banknote} disabled={!!busy} onClick={() => setCashPrompt({ installment: inst, note: '' })}>
                        دفع نقدي
                      </Button>
                      <IconButton icon={CalendarClock} label="تأجيل هذا القسط وما بعده شهراً" tone="indigo" loading={busy === `postpone_${inst.id}`} disabled={!!busy} onClick={() => postponeFrom(inst)} />
                      <IconButton icon={Pencil} label="تعديل قيمة القسط" tone="sky" disabled={!!busy} onClick={() => setAmountPrompt({ installment: inst, amount: Number(inst.amount) })} />
                    </>
                  ) : (
                    <>
                      <IconButton icon={Undo2} label="التراجع عن السداد" tone="amber" loading={busy === `revert_${inst.id}`} disabled={!!busy} onClick={() => revertPayment(inst)} />
                      <IconButton icon={Trash2} label="حذف القسط المسدد نهائياً" tone="rose" loading={busy === `delete_${inst.id}`} disabled={!!busy} onClick={() => deletePaidInstallment(inst)} />
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        </Modal>
      )}

      {/* Edit loan */}
      {editDraft && (
        <Modal title="تعديل السلفة وإعادة الجدولة" subtitle="تُحذف الأقساط غير المدفوعة ويُعاد توليدها ابتداءً من الشهر القادم" icon={Pencil} tone="sky" onClose={() => setEditDraft(null)}>
          <form onSubmit={submitEdit} className="grid grid-cols-2 gap-4">
            <Field label="المبلغ الإجمالي (د.ع)">
              <AmountInput required value={editDraft.amount} onValueChange={(v) => setEditDraft({ ...editDraft, amount: v })} />
            </Field>
            <Field label="القسط الشهري (د.ع)">
              <AmountInput required value={editDraft.installmentAmount} onValueChange={(v) => setEditDraft({ ...editDraft, installmentAmount: v })} />
            </Field>
            <Field label="عدد الأقساط الكلي">
              <AmountInput required value={editDraft.installmentCount} onValueChange={(v) => setEditDraft({ ...editDraft, installmentCount: v })} />
            </Field>
            <Field label="المبلغ المتبقي (د.ع)">
              <AmountInput required value={editDraft.remainingAmount} onValueChange={(v) => setEditDraft({ ...editDraft, remainingAmount: v })} />
            </Field>
            <div className="col-span-2">
              <ModalFooter onCancel={() => setEditDraft(null)} loading={busy === 'edit'} submitLabel="حفظ وإعادة الجدولة" submitIcon={Save} />
            </div>
          </form>
        </Modal>
      )}

      {/* Cash payment */}
      {cashPrompt && (
        <Modal title="تسجيل سداد نقدي" subtitle={`قيمة القسط: ${formatIQD(cashPrompt.installment.amount)}`} icon={Banknote} tone="emerald" size="sm" onClose={() => setCashPrompt(null)}>
          <form onSubmit={recordCash} className="space-y-4">
            <Field label="ملاحظة (اختياري)" hint="يُخصم القسط من الرصيد فوراً ولا يُستقطع من الراتب القادم.">
              <Input value={cashPrompt.note} onChange={(e) => setCashPrompt({ ...cashPrompt, note: e.target.value })} placeholder="مثال: وصل استلام رقم 12" />
            </Field>
            <ModalFooter onCancel={() => setCashPrompt(null)} loading={busy === 'cash'} submitLabel="تأكيد السداد" variant="success" />
          </form>
        </Modal>
      )}

      {/* Edit installment amount */}
      {amountPrompt && (
        <Modal title="تعديل قيمة القسط" icon={Pencil} tone="sky" size="sm" onClose={() => setAmountPrompt(null)}>
          <form onSubmit={updateInstallmentAmount} className="space-y-4">
            <Field label="المبلغ الجديد (د.ع)">
              <AmountInput required autoFocus value={amountPrompt.amount} onValueChange={(v) => setAmountPrompt({ ...amountPrompt, amount: v })} />
            </Field>
            <ModalFooter onCancel={() => setAmountPrompt(null)} loading={busy === 'amount'} submitLabel="حفظ التعديل" />
          </form>
        </Modal>
      )}
    </div>
  );
}
