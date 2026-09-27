'use client';

import type { Loan, LoanInstallment } from '@/lib/db-types';
import { paidAmount, sortInstallments } from '../logic';

interface LoanStatementPrintProps {
  selectedLoanForInstallments: Loan;
}

/** كشف حساب السلفة للطباعة فقط (مخفي على الشاشة). */
export function LoanStatementPrint({ selectedLoanForInstallments }: LoanStatementPrintProps) {
  return (
    <div className="hidden print:block text-slate-900 text-right p-8 font-sans bg-white min-h-screen" dir="rtl">
      {/* Header */}
      <div className="text-center border-b-2 border-slate-950 pb-6 mb-6">
        <h1 className="text-2xl font-black mb-2">كشف حساب أقساط وسلف الموظفين</h1>
        <h2 className="text-lg font-bold text-slate-700">قسم ادارة موظفين شركة بترى</h2>
        <p className="text-[10px] text-slate-500 mt-1">تاريخ استخراج الكشف: {new Date().toLocaleDateString('ar-IQ')} {new Date().toLocaleTimeString('ar-IQ')}</p>
      </div>

      {/* Employee & Loan info details */}
      <div className="grid grid-cols-2 gap-4 border border-slate-300 p-4 rounded-xl mb-6 bg-slate-50">
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">اسم الموظف:</span>
          <span className="font-black text-sm text-slate-950">{selectedLoanForInstallments.employees?.full_name}</span>
        </div>
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">المبلغ الإجمالي للسلفة:</span>
          <span className="font-black text-sm text-slate-950">{Number(selectedLoanForInstallments.amount).toLocaleString()} د.ع</span>
        </div>
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">إجمالي ما تم سداده:</span>
          <span className="font-black text-sm text-emerald-800">
            {paidAmount(selectedLoanForInstallments).toLocaleString()} د.ع
          </span>
        </div>
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">المبلغ المتبقي للسداد:</span>
          <span className="font-black text-sm text-amber-800">{Number(selectedLoanForInstallments.remaining_amount).toLocaleString()} د.ع</span>
        </div>
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">القسط الشهري الافتراضي:</span>
          <span className="font-black text-sm text-slate-950">{Number(selectedLoanForInstallments.installment_amount).toLocaleString()} د.ع</span>
        </div>
        <div>
          <span className="font-bold text-slate-600 block text-[10px] mb-0.5">حالة السلفة الحالية:</span>
          <span className="font-black text-sm text-slate-950">
            {Number(selectedLoanForInstallments.remaining_amount) <= 0 ? 'مسددة بالكامل ✅' : 'جارية السداد ⏳'}
          </span>
        </div>
      </div>

      {/* Details table */}
      <h3 className="font-bold text-xs mb-3">جدول تفاصيل الدفعات والأقساط:</h3>
      <table className="w-full border-collapse border border-slate-400 text-xs">
        <thead>
          <tr className="bg-slate-100 text-slate-900 font-bold">
            <th className="border border-slate-400 p-2 text-right">رقم القسط</th>
            <th className="border border-slate-400 p-2 text-right">تاريخ الاستحقاق</th>
            <th className="border border-slate-400 p-2 text-right">مبلغ القسط</th>
            <th className="border border-slate-400 p-2 text-right">حالة السداد</th>
            <th className="border border-slate-400 p-2 text-right">طريقة الدفع</th>
            <th className="border border-slate-400 p-2 text-right">تاريخ الدفع الفعلي</th>
            <th className="border border-slate-400 p-2 text-right">ملاحظات وتفاصيل الدفع</th>
          </tr>
        </thead>
        <tbody>
          {sortInstallments(selectedLoanForInstallments.loan_installments).map((inst: LoanInstallment, idx: number) => (
              <tr key={inst.id} className="border-b border-slate-300">
                <td className="border border-slate-400 p-2 font-bold">قسط #{idx + 1}</td>
                <td className="border border-slate-400 p-2 font-mono">{inst.due_date}</td>
                <td className="border border-slate-400 p-2 font-bold">{Number(inst.amount).toLocaleString()} د.ع</td>
                <td className="border border-slate-400 p-2 font-bold">
                  {inst.is_paid ? 'مدفوع' : 'غير مدفوع'}
                </td>
                <td className="border border-slate-400 p-2">
                  {inst.is_paid 
                    ? (inst.payment_type === 'cash' ? 'نقدي (كاش)' : 'استقطاع راتب')
                    : '-'
                  }
                </td>
                <td className="border border-slate-400 p-2">
                  {inst.paid_at ? new Date(inst.paid_at).toLocaleDateString('ar-IQ') : '-'}
                </td>
                <td className="border border-slate-400 p-2 text-slate-700">
                  {inst.payment_note || '-'}
                </td>
              </tr>
            ))}
        </tbody>
      </table>

      {/* Footer signature line */}
      <div className="grid grid-cols-2 gap-12 mt-20 text-[11px] text-center">
        <div>
          <p className="font-bold mb-12">توقيع المستلم (الموظف)</p>
          <p className="border-t border-slate-400 pt-2 w-48 mx-auto">التوقيع:</p>
        </div>
        <div>
          <p className="font-bold mb-12">اعتماد قسم الحسابات والموارد البشرية</p>
          <p className="border-t border-slate-400 pt-2 w-48 mx-auto">الختم والتوقيع:</p>
        </div>
      </div>
    </div>
  );
}
