import { Banknote, CalendarRange, Clock, Info, Plus, Printer, RotateCcw, TrendingDown, TrendingUp } from 'lucide-react';
import type { BonusDeduction } from '@/lib/db-types';
import { Badge, Button, InfoNote, Modal, StatTile, type Tone } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import type { PayrollRow } from '../calc';

type Props = {
  row: PayrollRow;
  startDate: string;
  endDate: string;
  onClose: () => void;
  onAddAdjustment: (type: 'bonus' | 'deduction') => void;
  onToggleExcuse: (date: string) => void;
};

function dayTone(status: string): Tone {
  if (status.includes('حاضر') || status.includes('معفى')) return 'emerald';
  if (status.includes('غياب')) return 'rose';
  if (status.includes('إجازة')) return 'sky';
  if (status.includes('تأخير') || status.includes('نصف')) return 'amber';
  return 'slate';
}

function EntryList({ items, sign, tone, empty }: { items: BonusDeduction[]; sign: '+' | '−'; tone: 'emerald' | 'rose'; empty: string }) {
  if (items.length === 0) return <p className="text-center py-4 text-xs text-slate-500">{empty}</p>;
  return (
    <div className="space-y-2 max-h-[140px] overflow-y-auto">
      {items.map((b) => (
        <div key={b.id} className="p-2 rounded-xl bg-slate-950/40 border border-slate-800/80 text-xs flex justify-between items-start gap-2">
          <div>
            <p className="text-white font-bold">{b.reason || (sign === '+' ? 'مكافأة' : 'خصم إداري')}</p>
            <p className="text-[10px] text-slate-500 mt-0.5" dir="ltr">{b.issue_date || '-'}</p>
          </div>
          <span className={`font-mono font-bold shrink-0 ${tone === 'emerald' ? 'text-emerald-300' : 'text-rose-300'}`}>
            {sign}{Number(b.amount).toLocaleString('en-US')}
          </span>
        </div>
      ))}
    </div>
  );
}

/** تفاصيل حضور وخصومات موظف خلال الدورة مع إمكانية إعفاء أيام الغياب. */
export function AttendanceBreakdownModal({ row, startDate, endDate, onClose, onAddAdjustment, onToggleExcuse }: Props) {
  const lateHint = [row.latesCount > 0 && `${row.latesCount} تأخير`, row.earlyExitsCount > 0 && `${row.earlyExitsCount} خروج مبكر`]
    .filter(Boolean).join(' · ');

  return (
    <Modal title="تفاصيل الحضور والخصومات" subtitle={`${row.full_name} · ${startDate} ← ${endDate}`} icon={CalendarRange} tone="indigo" size="lg" onClose={onClose}>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <StatTile label="أيام العمل" value={row.scheduledWorkDays} tone="slate" className="!p-3" />
        <StatTile label="الحضور" value={row.presentsCount} tone="emerald" className="!p-3" hint={lateHint || undefined} />
        <StatTile label="غيابات بخصم" value={row.absencesCount} tone="rose" className="!p-3" />
        <StatTile label="إجازات مدفوعة" value={row.paidLeavesCount} tone="sky" className="!p-3" />
      </div>

      <InfoNote tone="indigo" icon={Info} className="mb-5">
        <p>أجرة اليوم = {formatIQD(row.basic)} ÷ 30 = <b>{formatIQD(row.basic / 30)}</b></p>
        {row.absencesCount > 0 && <p>خصم الغياب = {row.absencesCount} يوم × أجرة اليوم = <b>{formatIQD(row.absenceDeduction)}</b></p>}
        {row.halfDaysCount > 0 && <p>خصم أنصاف الأيام = {row.halfDaysCount} × نصف أجرة يوم = <b>{formatIQD(row.halfDayDeduction)}</b></p>}
        {row.totalLateMinutes > 0 && (
          <p>خصم التأخير = {row.totalLateMinutes} دقيقة × (أجرة اليوم ÷ 480 دقيقة) = <b>{formatIQD(row.latenessDeduction)}</b></p>
        )}
        {row.totalEarlyExitMinutes > 0 && (
          <p>خصم الخروج المبكر = {row.totalEarlyExitMinutes} دقيقة = <b>{formatIQD(row.earlyExitDeduction)}</b></p>
        )}
        <p className="mt-1 pt-1 border-t border-indigo-500/20">إجمالي خصومات الدوام = <b className="text-white">{formatIQD(row.totalAttendanceDeductions)}</b></p>
      </InfoNote>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/5 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-bold text-emerald-300 flex items-center gap-1.5">
              <TrendingUp className="w-4 h-4" /> المكافآت ({formatIQD(row.totalBonuses)})
            </span>
            <Button size="xs" variant="soft-success" icon={Plus} onClick={() => onAddAdjustment('bonus')}>إضافة</Button>
          </div>
          <EntryList items={row.bonusesList ?? []} sign="+" tone="emerald" empty="لا توجد مكافآت خلال هذه الدورة" />
        </div>
        <div className="rounded-2xl border border-rose-500/20 bg-rose-500/5 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-bold text-rose-300 flex items-center gap-1.5">
              <TrendingDown className="w-4 h-4" /> الخصومات ({formatIQD((row.totalDeductions || 0) - (row.totalAttendanceDeductions || 0))})
            </span>
            <Button size="xs" variant="soft-danger" icon={Plus} onClick={() => onAddAdjustment('deduction')}>إضافة</Button>
          </div>
          <EntryList items={row.otherDeductionsList ?? []} sign="−" tone="rose" empty="لا توجد خصومات إدارية خلال هذه الدورة" />
        </div>
      </div>

      {row.loanDeduction > 0 && (
        <InfoNote tone="orange" icon={Banknote} className="mb-5">
          قسط السلفة المستحق لهذا الشهر: <b className="font-mono">−{row.loanDeduction.toLocaleString('en-US')} د.ع</b>
        </InfoNote>
      )}

      <p className="text-[11px] text-slate-400 mb-2 flex items-center gap-1.5">
        <Clock className="w-3.5 h-3.5" /> يوميات الدورة — يمكنك إعفاء أيام الغياب المعفاة إدارياً
      </p>
      <div className="max-h-[300px] overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
        {row.detailLogs.map((log) => (
          <div key={log.date} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
            <div className="flex items-center gap-2.5">
              <span className="font-mono text-slate-400" dir="ltr">{log.date}</span>
              <Badge tone={dayTone(log.status)}>{log.status}</Badge>
              {log.time !== '-' && <span className="text-slate-500 font-mono" dir="ltr">{log.time}</span>}
            </div>
            {log.isAbsenceDay ? (
              <Button size="xs" variant={log.isExcused ? 'soft-danger' : 'soft-success'} icon={RotateCcw} disabled={row.isIssued} onClick={() => onToggleExcuse(log.date)}>
                {log.isExcused ? 'إلغاء الإعفاء' : 'إعفاء'}
              </Button>
            ) : (
              <span className="text-[11px] text-slate-500 sm:text-left">{log.note}</span>
            )}
          </div>
        ))}
      </div>

      <div className="flex justify-between items-center pt-4 mt-5 border-t border-slate-800/80">
        <Button variant="secondary" icon={Printer} onClick={() => window.print()}>طباعة الكشف</Button>
        <Button variant="ghost" onClick={onClose}>إغلاق</Button>
      </div>
    </Modal>
  );
}
