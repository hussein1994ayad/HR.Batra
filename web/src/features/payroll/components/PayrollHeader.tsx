import { Archive, Banknote, CheckCircle2, Lock, LockOpen, Printer, TrendingDown, Wallet } from 'lucide-react';
import { Badge, Button, PageHeader, StatTile } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { currentPayrollMonth, payrollMonthOptions } from '../period';

type Props = {
  isMonthArchived: boolean;
  currentMonthVal: string;
  currentYearVal: string;
  startDate: string;
  endDate: string;
  paymentDate?: string | null;
  periodStatus?: 'open' | 'closed' | null;
  /** شهر قبل نظام المسيرات (كشوف قديمة للعرض). */
  legacy?: boolean;
  pendingDecisions: number;
  closing?: boolean;
  reopening?: boolean;
  onClosePeriod: () => void;
  onReopenPeriod: () => void;
  refreshing?: boolean;
  totals: { net: number; basic: number; deductions: number; loans: number };
  issuedCount: number;
  rowCount: number;
  branchLabel: string;
  onMonthChange: (month: string) => void;
};

/** العنوان واختيار الشهر والسنة والفترة المالية وإحصاءات الرواتب. */
export function PayrollHeader({
  isMonthArchived, currentMonthVal, currentYearVal, startDate, endDate, paymentDate, periodStatus, legacy, pendingDecisions,
  closing, reopening, onClosePeriod, onReopenPeriod, refreshing, totals, issuedCount, rowCount, branchLabel,
  onMonthChange,
}: Props) {
  const allIssued = issuedCount === rowCount && rowCount > 0;
  const selectedMonth = `${currentYearVal}-${currentMonthVal}`;
  // المسيرات بالتسلسل حول مسير اليوم، وتشمل المختار دائماً
  const options = payrollMonthOptions(currentPayrollMonth());
  const monthOptions = options.some((o) => o.value === selectedMonth)
    ? options
    : [...options, ...payrollMonthOptions(selectedMonth, 26, 0, 0)].sort((a, b) => a.value.localeCompare(b.value));
  return (
    <div className="space-y-6 print:hidden">
      <PageHeader
        icon={Banknote}
        tone="emerald"
        title="الرواتب والمكافآت"
        description={
          <span className="inline-flex flex-wrap items-center gap-1.5">
            {legacy ? 'كشوف قديمة (قبل نظام المسيرات)' : 'فترة المسير'}
            <span className="font-mono font-bold text-slate-200" dir="ltr">{startDate}</span>←
            <span className="font-mono font-bold text-slate-200" dir="ltr">{endDate}</span>
            {paymentDate && <span>· الصرف <span className="font-mono font-bold text-slate-200" dir="ltr">{paymentDate}</span></span>}
            {isMonthArchived ? (
              <Badge tone="violet"><Archive className="w-3 h-3" /> مؤرشف ومغلق مالياً</Badge>
            ) : periodStatus === 'closed' ? (
              <Badge tone="slate"><Lock className="w-3 h-3" /> المسير مغلق</Badge>
            ) : periodStatus === 'open' ? (
              <Badge tone="emerald" dot>المسير مفتوح</Badge>
            ) : null}
            {refreshing && <span className="text-indigo-300">· جاري التحديث...</span>}
          </span>
        }
        actions={
          <>
            <div className="flex items-center h-9 rounded-xl bg-slate-950/70 border border-slate-800 px-1">
              <select
                aria-label="مسير الشهر"
                value={selectedMonth}
                onChange={(e) => onMonthChange(e.target.value)}
                className="h-7 bg-transparent text-xs font-bold text-white outline-none cursor-pointer px-1 font-mono"
                dir="ltr"
              >
                {monthOptions.map((o) => (
                  <option key={o.value} value={o.value} className="bg-slate-900">{o.label}</option>
                ))}
              </select>
            </div>
            {!isMonthArchived && !legacy && periodStatus === 'open' && (
              <Button size="sm" variant="soft" icon={Lock} loading={closing} onClick={onClosePeriod}>
                إغلاق المسير
              </Button>
            )}
            {!isMonthArchived && !legacy && periodStatus === 'closed' && (
              <Button size="sm" variant="soft" icon={LockOpen} loading={reopening} onClick={onReopenPeriod}>
                إعادة فتح
              </Button>
            )}
            <Button size="sm" variant="secondary" icon={Printer} onClick={() => window.print()}>
              طباعة الكشف
            </Button>
          </>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="صافي الرواتب" value={formatIQD(totals.net)} icon={Wallet} tone="emerald" hint={branchLabel} />
        <StatTile label="الرواتب الأساسية" value={formatIQD(totals.basic)} icon={Banknote} tone="indigo" />
        <StatTile label="الخصومات والسلف" value={formatIQD(totals.deductions + totals.loans)} icon={TrendingDown} tone="rose" />
        <StatTile label="الرواتب المعتمدة" value={`${issuedCount} / ${rowCount}`} icon={CheckCircle2} tone={allIssued ? 'emerald' : 'amber'}
          hint={pendingDecisions > 0 ? `${pendingDecisions} حركة بانتظار قرارك` : undefined} />
      </div>
    </div>
  );
}
