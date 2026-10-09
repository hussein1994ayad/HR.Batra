import { AlertTriangle, Banknote, CalendarRange, Check, Clock, Info, Plus, Printer, TrendingDown, TrendingUp, X } from 'lucide-react';
import { Badge, Button, InfoNote, Modal, StatTile, type Tone } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { installmentOrigin } from '@/features/loans/logic';
import { attentionReasons, DECIDABLE, describeEvent, type EntryItem, type PayrollEvent, type PayrollRow } from '../calc';
import { arabicDate, payrollMonthName, payrollMonthOfDate } from '../period';

type Props = {
  row: PayrollRow;
  startDate: string;
  endDate: string;
  locked: boolean;
  actionLoading: string | null;
  onClose: () => void;
  onAddAdjustment: (type: 'bonus' | 'deduction') => void;
  onDecide: (eventId: string, approve: boolean) => void;
  /** ترك العمل وعليه سلفة: يخصم الباقي (أو الممكن) من آخر راتب. */
  onSettleExit?: () => void;
};

const STATUS: Record<PayrollEvent['status'], { label: string; tone: Tone }> = {
  pending: { label: 'بانتظار القرار', tone: 'amber' },
  approved: { label: 'محتسب', tone: 'rose' },
  ignored: { label: 'معفى', tone: 'emerald' },
  void: { label: 'ملغى', tone: 'slate' },
};

function statusOf(e: PayrollEvent) {
  if (e.status === 'approved' && e.direction === 1) return { label: 'مضاف', tone: 'emerald' as Tone };
  if (e.status === 'approved' && e.direction === 0) return { label: 'بدون أثر مالي', tone: 'sky' as Tone };
  return STATUS[e.status];
}

function EntryList({ items, sign, tone, empty }: { items: EntryItem[]; sign: '+' | '−'; tone: 'emerald' | 'rose'; empty: string }) {
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

/** تفاصيل حركات موظف في المسير (غياب، تأخير، خروج مبكر، إضافي...) مع قرار الإدارة على المعلّق منها. */
export function AttendanceBreakdownModal({ row, startDate, endDate, locked, actionLoading, onClose, onAddAdjustment, onDecide, onSettleExit }: Props) {
  const reasons = attentionReasons(row).filter((r) => r.kind !== 'decisions');
  const lateHint = [row.latesCount > 0 && `${row.latesCount} تأخير`, row.earlyExitsCount > 0 && `${row.earlyExitsCount} خروج مبكر`]
    .filter(Boolean).join(' · ');
  const canDecide = !locked && !row.isIssued;

  return (
    <Modal title={`تفاصيل راتب ${row.full_name}`}
      subtitle={`من ${arabicDate(startDate)} إلى ${arabicDate(endDate)}${row.scheduledDays > 0 ? ` · داوم ${row.attendedDays} من ${row.scheduledDays} يوم` : ''}`}
      icon={CalendarRange} tone="indigo" size="lg" onClose={onClose}>
      {reasons.length > 0 && (
        <InfoNote tone="amber" icon={AlertTriangle} className="mb-5">
          {reasons.map((r) => <p key={r.kind}>{r.text}</p>)}
        </InfoNote>
      )}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <StatTile label="بانتظار القرار" value={row.pendingCount} tone={row.pendingCount > 0 ? 'amber' : 'slate'} className="!p-3" />
        <StatTile label="غيابات بخصم" value={row.absencesCount} tone="rose" className="!p-3" hint={lateHint || undefined} />
        <StatTile label="دقائق التأخير" value={row.totalLateMinutes} tone="amber" className="!p-3" />
        <StatTile label="إجازات مدفوعة" value={row.paidLeavesCount} tone="sky" className="!p-3" />
      </div>

      <InfoNote tone="indigo" icon={Info} className="mb-5">
        <p>أجر اليوم = {formatIQD(row.monthlySalary)} ÷ 30 = <b>{formatIQD(row.dailyRate)}</b></p>
        <p>
          أجر الدقيقة = أجر اليوم ÷ {row.shiftMinutes} دقيقة دوام = <b>{row.minuteRate.toLocaleString('en-US', { maximumFractionDigits: 2 })} د.ع</b>
        </p>
        {row.employedDays < row.periodDays && (
          <p>الأساسي = {row.employedDays} يوم خدمة × أجر اليوم = <b>{formatIQD(row.basic)}</b></p>
        )}
        {row.absenceDeduction > 0 && <p>خصم الغياب = {row.absencesCount} يوم = <b>{formatIQD(row.absenceDeduction)}</b></p>}
        {row.latenessDeduction > 0 && <p>خصم التأخير = {row.totalLateMinutes} دقيقة = <b>{formatIQD(row.latenessDeduction)}</b></p>}
        {row.earlyExitDeduction > 0 && <p>خصم الخروج المبكر = {row.totalEarlyExitMinutes} دقيقة = <b>{formatIQD(row.earlyExitDeduction)}</b></p>}
        {row.unpaidLeaveDeduction > 0 && <p>إجازات بدون راتب = <b>{formatIQD(row.unpaidLeaveDeduction)}</b></p>}
        <p className="mt-1 pt-1 border-t border-indigo-500/20">إجمالي خصومات الدوام = <b className="text-white">{formatIQD(row.totalAttendanceDeductions)}</b></p>
      </InfoNote>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/5 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-bold text-emerald-300 flex items-center gap-1.5">
              <TrendingUp className="w-4 h-4" /> المكافآت والإضافي ({formatIQD(row.totalBonuses)})
            </span>
            {!locked && <Button size="xs" variant="soft-success" icon={Plus} onClick={() => onAddAdjustment('bonus')}>إضافة</Button>}
          </div>
          <EntryList items={row.bonusesList} sign="+" tone="emerald" empty="لا توجد مكافآت خلال هذا المسير" />
        </div>
        <div className="rounded-2xl border border-rose-500/20 bg-rose-500/5 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-bold text-rose-300 flex items-center gap-1.5">
              <TrendingDown className="w-4 h-4" /> الخصومات ({formatIQD(row.totalDeductions - row.totalAttendanceDeductions)})
            </span>
            {!locked && <Button size="xs" variant="soft-danger" icon={Plus} onClick={() => onAddAdjustment('deduction')}>إضافة</Button>}
          </div>
          <EntryList items={row.otherDeductionsList} sign="−" tone="rose" empty="لا توجد خصومات إدارية خلال هذا المسير" />
        </div>
      </div>

      {(row.loanDeduction > 0 || row.loanBalanceAfterExit > 0) && (
        <div className="mb-5 rounded-2xl border border-orange-500/20 bg-orange-500/5 p-4 space-y-2 text-xs">
          <p className="font-bold text-orange-300 flex items-center gap-1.5">
            <Banknote className="w-4 h-4" /> سلف تنخصم بهذا الراتب: −{row.loanDeduction.toLocaleString('en-US')} د.ع
          </p>
          {row.loanItems.map((i) => (
            <div key={i.installment_id} className="flex flex-wrap items-center justify-between gap-2 text-slate-300">
              <span>
                قسط {payrollMonthName(payrollMonthOfDate(i.due_date))} من سلفة {Number(i.loan_amount).toLocaleString('en-US')}
                {installmentOrigin({ ...i, is_paid: false }) && <Badge tone="amber" className="ms-2">{installmentOrigin({ ...i, is_paid: false })}</Badge>}
                {i.note && <span className="text-slate-500"> · {i.note}</span>}
              </span>
              <b className="font-mono text-orange-200">−{Number(i.amount).toLocaleString('en-US')}</b>
            </div>
          ))}
          <p className="text-slate-500">المؤجّل والمسدد نقداً ما ينخصم من الراتب. التعديل من صفحة السلف.</p>
          {row.loanBalanceAfterExit > 0 && (
            <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-orange-500/20">
              <span className="text-rose-300">ترك العمل وباقي عليه {row.loanBalanceAfterExit.toLocaleString('en-US')} د.ع بعد هذا الراتب.</span>
              {onSettleExit && !locked && !row.isIssued && (
                <Button size="xs" variant="soft-danger" loading={actionLoading === `settle_${row.id}`} onClick={onSettleExit}>
                  اخصم الباقي من آخر راتب
                </Button>
              )}
            </div>
          )}
        </div>
      )}

      <p className="text-[11px] text-slate-400 mb-2 flex items-center gap-1.5">
        <Clock className="w-3.5 h-3.5" /> حركات المسير — الغياب والتأخير والخروج المبكر لا تُخصم إلا بعد اعتمادك
      </p>
      <div className="max-h-[300px] overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
        {row.events.length === 0 && <p className="text-center py-6 text-xs text-slate-500">لا توجد حركات في هذا المسير</p>}
        {row.events.map((e) => {
          const st = statusOf(e);
          const busy = actionLoading === `decide_${e.id}`;
          const decidable = canDecide && e.status === 'pending' && DECIDABLE.includes(e.event_type) && !e.salary_slip_id;
          return (
            <div key={e.id} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-mono text-slate-400" dir="ltr">{e.event_date}</span>
                <span className="font-bold text-white">{describeEvent(e)}</span>
                <Badge tone={st.tone}>{st.label}</Badge>
                {e.carried_from && <Badge tone="violet">مرحّل من {e.carried_from}</Badge>}
                {e.notes && <span className="text-slate-500">{e.notes}</span>}
              </div>
              <div className="flex items-center gap-2 shrink-0">
                {Number(e.amount) > 0 && (
                  <span className={`font-mono font-bold ${e.direction === 1 ? 'text-emerald-300' : 'text-rose-300'}`}>
                    {e.direction === 1 ? '+' : '−'}{Math.round(Number(e.amount)).toLocaleString('en-US')}
                  </span>
                )}
                {decidable && (
                  <>
                    <Button size="xs" variant={e.direction === 1 ? 'soft-success' : 'soft-danger'} icon={Check} loading={busy}
                      onClick={() => onDecide(e.id, true)}>
                      {e.direction === 1 ? 'اعتماد' : e.event_type === 'missing_punch' ? 'تأكيد' : 'خصم'}
                    </Button>
                    <Button size="xs" variant="soft-success" icon={X} disabled={busy} onClick={() => onDecide(e.id, false)}>
                      {e.direction === 1 ? 'رفض' : 'إعفاء'}
                    </Button>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>

      <div className="flex justify-between items-center pt-4 mt-5 border-t border-slate-800/80">
        <Button variant="secondary" icon={Printer} onClick={() => window.print()}>طباعة الكشف</Button>
        <Button variant="ghost" onClick={onClose}>إغلاق</Button>
      </div>
    </Modal>
  );
}
