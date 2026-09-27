import { AlertTriangle, CheckCircle2, Info, Users } from 'lucide-react';
import { EmptyState, InfoNote, Modal, ModalFooter, StatTile } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { sumPayroll, type PayrollRow } from '../calc';

type Props = {
  branchName: string;
  selectedMonth: string;
  startDate: string;
  endDate: string;
  pendingRows: PayrollRow[];
  approving: boolean;
  onClose: () => void;
  onConfirm: () => void;
};

/** تأكيد اعتماد كل رواتب الفرع غير المعتمدة دفعة واحدة. */
export function BulkApproveModal({ branchName, selectedMonth, startDate, endDate, pendingRows, approving, onClose, onConfirm }: Props) {
  const totals = sumPayroll(pendingRows);
  return (
    <Modal title="اعتماد الرواتب دفعة واحدة" subtitle={`${branchName || 'جميع الفروع'} · ${startDate} ← ${endDate}`} icon={Users} tone="emerald" onClose={onClose}>
      {pendingRows.length === 0 ? (
        <>
          <EmptyState icon={CheckCircle2} tone="emerald" title="كل الرواتب معتمدة" description={`تم اعتماد كشوف جميع الموظفين لشهر ${selectedMonth}.`} />
          <ModalFooter onCancel={onClose} cancelLabel="إغلاق" />
        </>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 mb-4">
            <StatTile label="عدد الموظفين" value={pendingRows.length} tone="slate" className="!p-3" />
            <StatTile label="الرواتب الأساسية" value={formatIQD(totals.basic)} tone="indigo" className="!p-3" />
            <StatTile label="المكافآت" value={formatIQD(totals.bonuses)} tone="emerald" className="!p-3" />
            <StatTile label="الخصومات والسلف" value={formatIQD(totals.deductions + totals.loans)} tone="rose" className="!p-3" />
          </div>
          <div className="rounded-2xl bg-emerald-500/5 border border-emerald-500/20 p-4 text-center mb-4">
            <p className="text-[11px] text-slate-400 mb-1">إجمالي الصافي المستحق</p>
            <p className="text-2xl font-extrabold text-emerald-300">{formatIQD(totals.net)}</p>
          </div>
          {pendingRows.some((r) => r.isNetNegative || r.unconfirmedAbsencesCount > 0) && (
            <InfoNote tone="amber" icon={AlertTriangle} className="mb-2">
              بعض الموظفين لديهم تنبيهات (صافي سالب أو غياب غير مثبت). راجعهم قبل الاعتماد.
            </InfoNote>
          )}
          <InfoNote tone="slate" icon={Info}>
            يُعتمد كل كشف في معاملة واحدة على السيرفر، وتُحدَّث أقساط السلف والخصومات تلقائياً.
          </InfoNote>
          <ModalFooter
            onCancel={onClose}
            onSubmit={onConfirm}
            loading={approving}
            loadingLabel="جاري الاعتماد..."
            submitLabel={`اعتماد ${pendingRows.length} راتب`}
            variant="success"
            submitIcon={CheckCircle2}
          />
        </>
      )}
    </Modal>
  );
}
