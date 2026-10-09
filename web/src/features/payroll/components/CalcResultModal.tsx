import { AlertTriangle, Calculator, Gavel, Info } from 'lucide-react';
import { InfoNote, Modal, ModalFooter, StatTile } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { attentionReasons, sumPayroll, type PayrollRow } from '../calc';
import { arabicDate, payrollMonthName } from '../period';

type Props = {
  selectedMonth: string;
  endDate: string;
  rows: PayrollRow[];
  onClose: () => void;
  onShowDecisions: () => void;
};

/** نتيجة «احتساب الرواتب»: شنو انحسب، شكد الصافي، وشنو باقي ينتظر قرارك (ما ينخصم شي بدون قرار). */
export function CalcResultModal({ selectedMonth, endDate, rows, onClose, onShowDecisions }: Props) {
  const totals = sumPayroll(rows);
  const pending = rows.reduce((acc, r) => acc + r.pendingCount, 0);
  const attention = rows.filter((r) => attentionReasons(r).some((a) => a.kind !== 'decisions')).length;
  return (
    <Modal title={`نتيجة احتساب رواتب ${payrollMonthName(selectedMonth)}`} subtitle={`${rows.length} موظف · الأرقام لحد اليوم`} icon={Calculator} tone="indigo" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3 mb-4">
        <StatTile label="الرواتب الأساسية" value={formatIQD(totals.basic)} tone="indigo" className="!p-3" />
        <StatTile label="خصومات الدوام المثبتة" value={formatIQD(totals.attendanceDeductions)} tone="rose" className="!p-3" />
        <StatTile label="أقساط السلف" value={formatIQD(totals.loans)} tone="amber" className="!p-3" />
        <StatTile label="مكافآت − خصومات أخرى" value={formatIQD(totals.bonuses - totals.otherDeductions)} tone="emerald" className="!p-3" />
      </div>
      <div className="rounded-2xl bg-emerald-500/5 border border-emerald-500/20 p-4 text-center mb-4">
        <p className="text-[11px] text-slate-400 mb-1">الصافي اللي ينصرف للموظفين</p>
        <p className="text-2xl font-extrabold text-emerald-300">{formatIQD(totals.net)}</p>
      </div>
      {pending > 0 && (
        <InfoNote tone="amber" icon={Gavel} className="mb-2">
          {pending} حركة (غياب، تأخير، بصمة ناقصة) تنتظر قرارك: خصم أو إعفاء. ما انخصمت بعد، ولا تنخصم إلا إذا قررت «خصم».
        </InfoNote>
      )}
      {attention > 0 && (
        <InfoNote tone="amber" icon={AlertTriangle} className="mb-2">
          {attention} موظف يحتاج نظرة (ما داوم، صافي سالب، بيانات ناقصة...).
        </InfoNote>
      )}
      <InfoNote tone="slate" icon={Info}>
        الاحتساب يحدّث الأرقام بس، وما يثبّت شي. الراتب يثبت وتنقطع السلفة لما تعتمده
        {endDate ? ` (الاعتماد من بعد ${arabicDate(endDate)})` : ''}.
      </InfoNote>
      <ModalFooter
        onCancel={onClose}
        cancelLabel="تمام"
        submitLabel={pending > 0 ? 'عرض القرارات' : undefined}
        submitIcon={Gavel}
        onSubmit={onShowDecisions}
      />
    </Modal>
  );
}
