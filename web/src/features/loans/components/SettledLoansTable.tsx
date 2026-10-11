'use client';

// سجل السلف المسددة (المؤرشفة): سجل مالي دائم مختصر لكل سلفة تسددت وانحذف سجلها التشغيلي — للعرض والإثبات.
// ما يدخل بأي حساب راتب: مبلغ كل قسط محفوظ أصلاً بكشف راتبه.

import { Download, Eye } from 'lucide-react';
import { formatDate, formatIQD } from '@/lib/format';
import { Avatar, Badge, Button, DataTable, IconButton, Modal, ModalFooter, TableEmpty } from '@/components/ui';
import { payrollMonthName } from '@/features/payroll/period';
import { loanRef } from '../logic';
import { downloadSettledLoanStatement } from '../statementExport';
import type { LoansState } from '../useLoans';

export function SettledLoansTable({ s }: { s: LoansState }) {
  const { displayedSettled, settledView, setSettledView } = s;
  return (
    <>
      <DataTable>
        <thead>
          <tr>
            <th>الموظف</th>
            <th>رقم السلفة</th>
            <th>المبلغ الأصلي</th>
            <th>مجموع المستقطع</th>
            <th>تاريخ التسوية</th>
            <th className="!text-left">الإجراءات</th>
          </tr>
        </thead>
        <tbody>
          {displayedSettled.length === 0 ? (
            <TableEmpty colSpan={6}>لا توجد سلف مؤرشفة. السلفة المسددة تتأرشف من تبويب «المكتملة».</TableEmpty>
          ) : (
            displayedSettled.map((loan) => (
              <tr key={loan.id}>
                <td>
                  <div className="flex items-center gap-2.5">
                    <Avatar name={loan.employee_name} size="sm" />
                    <div>
                      <span className="font-bold text-white">{loan.employee_name}</span>
                      {loan.employee_code && <span className="block text-[10px] text-slate-500">{loan.employee_code}</span>}
                    </div>
                  </div>
                </td>
                <td className="font-mono text-slate-300" dir="ltr">{loanRef(loan.loan_no)}</td>
                <td className="font-bold text-slate-200">{formatIQD(loan.amount)}</td>
                <td>
                  <span className="font-bold text-emerald-300">{formatIQD(loan.total_deducted)}</span>
                  <span className="block text-[10px] text-slate-500">{loan.installments.length} استقطاع · الباقي 0</span>
                </td>
                <td className="font-mono text-slate-300" dir="ltr">{formatDate(loan.settled_at)}</td>
                <td className="!text-left">
                  <div className="flex justify-end gap-1.5">
                    <Button size="sm" variant="soft" icon={Eye} onClick={() => setSettledView(loan)}>التفاصيل</Button>
                    <IconButton icon={Download} label="تنزيل الكشف Excel" onClick={() => downloadSettledLoanStatement(loan)} />
                  </div>
                </td>
              </tr>
            ))
          )}
        </tbody>
      </DataTable>

      {settledView && (
        <Modal
          title={`سلفة ${loanRef(settledView.loan_no)} — ${settledView.employee_name}`}
          subtitle={`المبلغ ${formatIQD(settledView.amount)} · تسددت ${formatDate(settledView.settled_at)} · تأرشفت ${formatDate(settledView.archived_at)}`}
          icon={Eye}
          tone="emerald"
          onClose={() => setSettledView(null)}
        >
          <ul className="divide-y divide-slate-800 text-xs">
            {settledView.installments.map((inst, i) => (
              <li key={`${inst.due_date}_${i}`} className="py-2.5 flex items-center justify-between gap-3">
                <div>
                  <p className="font-bold text-slate-200">رواتب {payrollMonthName(inst.payroll_month)}</p>
                  <p className="text-[10px] text-slate-500">
                    {inst.paid_at ? `تسدد ${formatDate(inst.paid_at)}` : `استحقاق ${inst.due_date}`}{inst.note ? ` · ${inst.note}` : ''}
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Badge tone={inst.method === 'salary' ? 'indigo' : 'emerald'}>{inst.method === 'salary' ? 'خصم من الراتب' : 'نقداً'}</Badge>
                  <span className="font-mono font-bold text-white">{formatIQD(inst.amount)}</span>
                </div>
              </li>
            ))}
          </ul>
          <div className="mt-3 rounded-2xl bg-emerald-500/5 border border-emerald-500/20 p-3 flex items-center justify-between text-xs">
            <span className="text-slate-400">مجموع المستقطع</span>
            <span className="font-extrabold text-emerald-300">{formatIQD(settledView.total_deducted)} · الباقي 0</span>
          </div>
          <ModalFooter onCancel={() => setSettledView(null)} cancelLabel="إغلاق" submitLabel="تنزيل الكشف Excel" submitIcon={Download}
            onSubmit={() => downloadSettledLoanStatement(settledView)} />
        </Modal>
      )}
    </>
  );
}
