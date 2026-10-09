'use client';

// خطوات الرواتب بالترتيب (مثل أنظمة HR المعروفة): كل خطوة تبين شنو باقي وزرها المباشر، وتصير ✓ لما تخلص.
//   1) احتساب الرواتب  2) القرارات المعلّقة  3) التنبيهات  4) اعتماد الرواتب  5) إغلاق المسير

import { AlertTriangle, Calculator, CheckCircle2, Gavel, Lock, Stamp } from 'lucide-react';
import { Button, cn } from '@/components/ui';
import { arabicDate, baghdadToday } from '../period';
import type { PayrollStatusFilter } from './PayrollToolbar';

type Props = {
  pendingDecisions: number;
  attentionCount: number;
  issuedCount: number;
  rowCount: number;
  periodStatus?: 'open' | 'closed' | null;
  locked: boolean;
  closing?: boolean;
  onFilter: (f: PayrollStatusFilter) => void;
  /** رواتب تكدر تنعتمد هسه (بعد نهاية الفترة، أو آخر راتب لمن ترك) */
  approvableCount: number;
  /** آخر يوم بفترة الدوام: الاعتماد من اليوم اللي بعده */
  approveFrom: string;
  /** آخر «احتساب الرواتب» (ISO) أو فارغ */
  calculatedAt?: string | null;
  calculating?: boolean;
  onCalculate: () => void;
  onOpenBulk: () => void;
  onClosePeriod: () => void;
};

function Step({ n, done, active, icon: Icon, title, detail, action }: {
  n: number; done: boolean; active: boolean; icon: typeof Gavel; title: string; detail: string; action?: React.ReactNode;
}) {
  return (
    <div className={cn('flex-1 min-w-[200px] rounded-2xl border p-3 flex flex-col gap-2',
      done ? 'border-emerald-500/30 bg-emerald-500/5' : active ? 'border-amber-400/40 bg-amber-500/5' : 'border-slate-800 bg-slate-900/40')}>
      <div className="flex items-center gap-2">
        <span className={cn('w-6 h-6 rounded-full text-[11px] font-black flex items-center justify-center',
          done ? 'bg-emerald-500 text-slate-950' : active ? 'bg-amber-400 text-slate-950' : 'bg-slate-700 text-slate-300')}>
          {done ? '✓' : n}
        </span>
        <Icon className={cn('w-4 h-4', done ? 'text-emerald-300' : active ? 'text-amber-300' : 'text-slate-500')} />
        <span className="text-sm font-bold text-white">{title}</span>
      </div>
      <p className="text-xs text-slate-400">{detail}</p>
      {action}
    </div>
  );
}

export function PayrollSteps({
  pendingDecisions, attentionCount, issuedCount, rowCount, periodStatus, locked, closing, onFilter, approvableCount, approveFrom,
  calculatedAt, calculating, onCalculate, onOpenBulk, onClosePeriod,
}: Props) {
  const nextDay = approveFrom ? new Date(Date.parse(approveFrom + 'T00:00:00Z') + 86400000).toISOString().slice(0, 10) : '';
  // محسوبة اليوم = الأرقام حديثة (التحديث الليلي يغطي الأيام السابقة)
  const calcDate = calculatedAt ? new Date(calculatedAt) : null;
  const calculatedToday = !!calcDate && calcDate.toDateString() === new Date().toDateString();
  const calcLabel = calcDate
    ? `آخر احتساب ${arabicDate(baghdadToday(calcDate))} الساعة ${calcDate.toLocaleTimeString('ar-IQ-u-nu-latn', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Baghdad' })}.`
    : 'ما انحسبت بعد.';
  const decisionsDone = pendingDecisions === 0;
  const attentionDone = attentionCount === 0;
  const approvedDone = rowCount > 0 && issuedCount === rowCount;
  const closedDone = periodStatus === 'closed';
  const current = !calculatedToday && !approvedDone ? 1 : !decisionsDone ? 2 : !attentionDone ? 3 : !approvedDone ? 4 : !closedDone ? 5 : 0;
  return (
    <div className="flex flex-wrap gap-3 print:hidden" aria-label="خطوات اعتماد الرواتب">
      <Step n={1} done={calculatedToday || approvedDone} active={current === 1} icon={Calculator} title="احسب الرواتب"
        detail={`${calcLabel} يحسب الغيابات والبصمات الناقصة والخصومات والسلف لكل الموظفين.`}
        action={!locked && !approvedDone && (
          <Button size="xs" variant={calculatedToday ? 'soft' : 'primary'} icon={Calculator} loading={calculating} onClick={onCalculate}>
            احتساب الرواتب
          </Button>
        )} />
      <Step n={2} done={decisionsDone} active={current === 2} icon={Gavel} title="القرارات المعلّقة"
        detail={decisionsDone ? 'كل الغيابات والتأخيرات اتخذت قرارها.' : `${pendingDecisions} حركة (غياب/تأخير/بصمة) تنتظر: خصم أو إعفاء.`}
        action={!decisionsDone && <Button size="xs" variant="soft" onClick={() => onFilter('decisions')}>عرض الموظفين</Button>} />
      <Step n={3} done={attentionDone} active={current === 3} icon={AlertTriangle} title="راجع التنبيهات"
        detail={attentionDone ? 'ماكو شي غريب.' : `${attentionCount} موظف يحتاج نظرة (ما داوم، صافي سالب، ترك وعليه سلفة...).`}
        action={!attentionDone && <Button size="xs" variant="soft" onClick={() => onFilter('attention')}>عرضهم</Button>} />
      <Step n={4} done={approvedDone} active={current === 4} icon={Stamp} title="اعتمد الرواتب"
        detail={approvableCount === 0 && !approvedDone && nextDay
          ? `المعتمد ${issuedCount} من ${rowCount}. الاعتماد يتفعّل من ${arabicDate(nextDay)} (بعد نهاية الدوام المحسوب).`
          : `المعتمد ${issuedCount} من ${rowCount}. الاعتماد يثبّت الكشف ويستقطع أقساط السلف.`}
        action={!approvedDone && !locked && approvableCount > 0 && (
          <Button size="xs" variant="soft-success" icon={CheckCircle2} onClick={onOpenBulk}>اعتماد ({approvableCount})</Button>
        )} />
      <Step n={5} done={closedDone} active={current === 5} icon={Lock} title="أغلق المسير"
        detail={closedDone ? 'المسير مغلق، ما يتغير شي بيه.' : 'بعد الاعتماد: الإغلاق يقفل الشهر وأي حركة جديدة تروح للشهر الجاي.'}
        action={!closedDone && periodStatus === 'open' && approvedDone && (
          <Button size="xs" variant="soft" icon={Lock} loading={closing} onClick={onClosePeriod}>إغلاق المسير</Button>
        )} />
    </div>
  );
}
