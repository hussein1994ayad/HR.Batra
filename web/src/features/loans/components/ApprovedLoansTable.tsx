'use client';

// سجل السلف المعتمدة (جارية/مكتملة): نسبة السداد، المتبقي، القسط القادم، وفتح جدول الأقساط.

import { Calendar, CreditCard, Trash2 } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { Avatar, Badge, Button, Card, CardHeader, DataTable, IconButton, SearchInput, SegmentedTabs, TableEmpty } from '@/components/ui';
import { sortInstallments } from '../logic';
import type { LoansState } from '../useLoans';

export function ApprovedLoansTable({ s }: { s: LoansState }) {
  const { active, completed, displayed, tab, setTab, search, setSearch, busy, setScheduleLoanId, deleteLoan } = s;
  return (
    <>
    <Card>
      <CardHeader
        icon={CreditCard}
        tone="indigo"
        title="سجل السلف المعتمدة"
        description="اضغط على جدول الأقساط لتسجيل دفعة بأي مبلغ أو تأجيل قسط"
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
              const unpaid = sortInstallments(loan.loan_installments).filter((i) => !i.is_paid);
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
                    <div className="flex justify-end gap-1.5">
                      <Button size="sm" variant="soft" icon={Calendar} onClick={() => setScheduleLoanId(loan.id)}>
                        جدول الأقساط
                      </Button>
                      {tab === 'completed' && (
                        <IconButton icon={Trash2} label="حذف السجل نهائياً" tone="rose" loading={busy === `delete_loan_${loan.id}`} onClick={() => deleteLoan(loan)} />
                      )}
                    </div>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </DataTable>
    </Card>
    </>
  );
}
