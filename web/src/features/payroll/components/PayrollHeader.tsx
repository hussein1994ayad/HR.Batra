import { Archive, Banknote, CheckCircle2, ChevronLeft, ChevronRight, HandCoins, Lock, LockOpen, Printer, Wallet } from 'lucide-react';
import { Badge, Button, StatTile } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { arabicDate, currentPayrollMonth, payrollMonthName, payrollMonthOptions, shiftPayrollMonth } from '../period';

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
  reopening?: boolean;
  onReopenPeriod: () => void;
  refreshing?: boolean;
  totals: { net: number; basic: number; deductions: number; loans: number };
  issuedCount: number;
  rowCount: number;
  branchLabel: string;
  onMonthChange: (month: string) => void;
};

/**
 * رأس صفحة الرواتب بلغة مفهومة: «رواتب تشرين الأول 2026» وتحته جملة فترة الدوام ويوم الصرف،
 * وتنقّل بين الأشهر بأسهم، و3 أرقام بس (الصافي، المعتمد، السلف المستقطعة).
 */
export function PayrollHeader({
  isMonthArchived, currentMonthVal, currentYearVal, startDate, endDate, paymentDate, periodStatus, legacy,
  reopening, onReopenPeriod, refreshing, totals, issuedCount, rowCount, branchLabel, onMonthChange,
}: Props) {
  const allIssued = issuedCount === rowCount && rowCount > 0;
  const selectedMonth = `${currentYearVal}-${currentMonthVal}`;
  // المسيرات بالتسلسل حول مسير اليوم، وتشمل المختار دائماً
  const options = payrollMonthOptions(currentPayrollMonth());
  const monthOptions = options.some((o) => o.value === selectedMonth)
    ? options
    : [...options, ...payrollMonthOptions(selectedMonth, 0, 0)].sort((a, b) => a.value.localeCompare(b.value));
  return (
    <div className="space-y-5 print:hidden">
      <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-4">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <span className="w-11 h-11 rounded-2xl bg-emerald-500/15 text-emerald-300 flex items-center justify-center"><Banknote className="w-6 h-6" /></span>
            <h1 className="text-2xl font-black text-white">رواتب {payrollMonthName(selectedMonth)}</h1>
            {isMonthArchived ? (
              <Badge tone="violet"><Archive className="w-3 h-3" /> مؤرشف</Badge>
            ) : periodStatus === 'closed' ? (
              <Badge tone="slate"><Lock className="w-3 h-3" /> مغلق</Badge>
            ) : periodStatus === 'open' ? (
              <Badge tone="emerald" dot>مفتوح</Badge>
            ) : null}
          </div>
          <p className="text-sm text-slate-300">
            {legacy
              ? 'كشوف قديمة (قبل نظام المسيرات) للعرض فقط.'
              : <>يُحسب الدوام من <b className="text-white">{arabicDate(startDate)}</b> إلى <b className="text-white">{arabicDate(endDate)}</b>
                {paymentDate && <> · يوم الصرف <b className="text-white">{arabicDate(paymentDate)}</b></>}</>}
            {refreshing && <span className="text-indigo-300"> · جاري التحديث...</span>}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center h-10 rounded-xl bg-slate-950/70 border border-slate-800">
            <button type="button" aria-label="الشهر السابق" className="h-full px-2 text-slate-300 hover:text-white cursor-pointer"
              onClick={() => onMonthChange(shiftPayrollMonth(selectedMonth, -1))}>
              <ChevronRight className="w-4 h-4" />
            </button>
            <select
              aria-label="مسير الشهر"
              value={selectedMonth}
              onChange={(e) => onMonthChange(e.target.value)}
              className="h-full bg-transparent text-sm font-bold text-white outline-none cursor-pointer px-1"
            >
              {monthOptions.map((o) => (
                <option key={o.value} value={o.value} className="bg-slate-900">{o.label}</option>
              ))}
            </select>
            <button type="button" aria-label="الشهر التالي" className="h-full px-2 text-slate-300 hover:text-white cursor-pointer"
              onClick={() => onMonthChange(shiftPayrollMonth(selectedMonth, 1))}>
              <ChevronLeft className="w-4 h-4" />
            </button>
          </div>
          {!isMonthArchived && !legacy && periodStatus === 'closed' && (
            <Button size="sm" variant="soft" icon={LockOpen} loading={reopening} onClick={onReopenPeriod}>إعادة فتح</Button>
          )}
          <Button size="sm" variant="secondary" icon={Printer} onClick={() => window.print()}>طباعة</Button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <StatTile label="الصافي المطلوب صرفه" value={formatIQD(totals.net)} icon={Wallet} tone="emerald" hint={branchLabel} />
        <StatTile label="الرواتب المعتمدة" value={`${issuedCount} من ${rowCount}`} icon={CheckCircle2} tone={allIssued ? 'emerald' : 'amber'} />
        <StatTile label="أقساط السلف المستقطعة" value={formatIQD(totals.loans)} icon={HandCoins} tone="orange" />
      </div>
    </div>
  );
}
