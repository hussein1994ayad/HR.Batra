'use client';

// خطوات اعتماد الرواتب بالترتيب: كل خطوة تبين شنو باقي وزرها المباشر، وتصير ✓ لما تخلص.
//   1) القرارات المعلّقة  2) التنبيهات  3) اعتماد الرواتب  4) إغلاق المسير

import { AlertTriangle, CheckCircle2, Gavel, Lock, Stamp } from 'lucide-react';
import { Button, cn } from '@/components/ui';
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
  pendingDecisions, attentionCount, issuedCount, rowCount, periodStatus, locked, closing, onFilter, onOpenBulk, onClosePeriod,
}: Props) {
  const decisionsDone = pendingDecisions === 0;
  const attentionDone = attentionCount === 0;
  const approvedDone = rowCount > 0 && issuedCount === rowCount;
  const closedDone = periodStatus === 'closed';
  const current = !decisionsDone ? 1 : !attentionDone ? 2 : !approvedDone ? 3 : !closedDone ? 4 : 0;
  return (
    <div className="flex flex-wrap gap-3 print:hidden" aria-label="خطوات اعتماد الرواتب">
      <Step n={1} done={decisionsDone} active={current === 1} icon={Gavel} title="القرارات المعلّقة"
        detail={decisionsDone ? 'كل الغيابات والتأخيرات اتخذت قرارها.' : `${pendingDecisions} حركة (غياب/تأخير/بصمة) تنتظر: خصم أو إعفاء.`}
        action={!decisionsDone && <Button size="xs" variant="soft" onClick={() => onFilter('decisions')}>عرض الموظفين</Button>} />
      <Step n={2} done={attentionDone} active={current === 2} icon={AlertTriangle} title="راجع التنبيهات"
        detail={attentionDone ? 'ماكو شي غريب.' : `${attentionCount} موظف يحتاج نظرة (ما داوم، صافي سالب، ترك وعليه سلفة...).`}
        action={!attentionDone && <Button size="xs" variant="soft" onClick={() => onFilter('attention')}>عرضهم</Button>} />
      <Step n={3} done={approvedDone} active={current === 3} icon={Stamp} title="اعتمد الرواتب"
        detail={`المعتمد ${issuedCount} من ${rowCount}. الاعتماد يثبّت الكشف ويستقطع أقساط السلف.`}
        action={!approvedDone && !locked && (
          <Button size="xs" variant="soft-success" icon={CheckCircle2} disabled={issuedCount === rowCount} onClick={onOpenBulk}>اعتماد الباقي</Button>
        )} />
      <Step n={4} done={closedDone} active={current === 4} icon={Lock} title="أغلق المسير"
        detail={closedDone ? 'المسير مغلق، ما يتغير شي بيه.' : 'بعد الاعتماد: الإغلاق يقفل الشهر وأي حركة جديدة تروح للشهر الجاي.'}
        action={!closedDone && periodStatus === 'open' && approvedDone && (
          <Button size="xs" variant="soft" icon={Lock} loading={closing} onClick={onClosePeriod}>إغلاق المسير</Button>
        )} />
    </div>
  );
}
