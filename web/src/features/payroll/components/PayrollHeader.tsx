import { Archive, Banknote, CheckCircle2, Printer, TrendingDown, Wallet } from 'lucide-react';
import { Badge, Button, PageHeader, StatTile } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { ARABIC_MONTHS } from '@/lib/dates';

type Props = {
  isMonthArchived: boolean;
  currentMonthVal: string;
  currentYearVal: string;
  startDate: string;
  endDate: string;
  refreshing?: boolean;
  totals: { net: number; basic: number; deductions: number; loans: number };
  issuedCount: number;
  rowCount: number;
  branchLabel: string;
  onMonthChange: (month: string) => void;
};

/** العنوان واختيار الشهر والسنة والفترة المالية وإحصاءات الرواتب. */
export function PayrollHeader({
  isMonthArchived, currentMonthVal, currentYearVal, startDate, endDate, refreshing, totals, issuedCount, rowCount, branchLabel,
  onMonthChange,
}: Props) {
  const allIssued = issuedCount === rowCount && rowCount > 0;
  return (
    <div className="space-y-6 print:hidden">
      <PageHeader
        icon={Banknote}
        tone="emerald"
        title="الرواتب والمكافآت"
        description={
          <span className="inline-flex flex-wrap items-center gap-1.5">
            الدورة المالية
            <span className="font-mono font-bold text-slate-200" dir="ltr">{startDate}</span>←
            <span className="font-mono font-bold text-slate-200" dir="ltr">{endDate}</span>
            {isMonthArchived && <Badge tone="violet"><Archive className="w-3 h-3" /> مؤرشف ومغلق مالياً</Badge>}
            {refreshing && <span className="text-indigo-300">· جاري التحديث...</span>}
          </span>
        }
        actions={
          <>
            <div className="flex items-center gap-1 h-9 rounded-xl bg-slate-950/70 border border-slate-800 px-1">
              <select
                aria-label="الشهر"
                value={currentMonthVal}
                onChange={(e) => onMonthChange(`${currentYearVal}-${e.target.value}`)}
                className="h-7 bg-transparent text-xs font-bold text-white outline-none cursor-pointer px-1"
              >
                {Object.entries(ARABIC_MONTHS).map(([num, name]) => (
                  <option key={num} value={num} className="bg-slate-900">{name}</option>
                ))}
              </select>
              <select
                aria-label="السنة"
                value={currentYearVal}
                onChange={(e) => onMonthChange(`${e.target.value}-${currentMonthVal}`)}
                className="h-7 bg-transparent text-xs font-bold text-white outline-none cursor-pointer px-1 font-mono"
              >
                {Array.from({ length: 9 }, (_, i) => String(2024 + i)).map((y) => (
                  <option key={y} value={y} className="bg-slate-900">{y}</option>
                ))}
              </select>
            </div>
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
        <StatTile label="الرواتب المعتمدة" value={`${issuedCount} / ${rowCount}`} icon={CheckCircle2} tone={allIssued ? 'emerald' : 'amber'} />
      </div>
    </div>
  );
}
