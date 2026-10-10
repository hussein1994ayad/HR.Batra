import { Gavel } from 'lucide-react';
import { Avatar, Badge, Button, Card, CardHeader, DataTable, Input, TableEmpty } from '@/components/ui';
import { DEDUCT_REASONS, EXCUSE_REASONS } from '@/features/payroll/decisionReasons';
import { decisionKey } from '../logic';
import type { Decision } from '../types';

type Props = {
  decisionsList: Decision[];
  selectedReasons: Record<string, string>;
  busyKey?: string | null;
  onReasonChange: (key: string, value: string) => void;
  onDecide: (item: Decision, status: 'applied' | 'ignored', reason: string) => void;
};

/** قرارات الخصم أو الإعفاء لكل غياب وتأخير في الفترة. */
export function DecisionsTable({ decisionsList, selectedReasons, busyKey, onReasonChange, onDecide }: Props) {
  return (
    <Card>
      <CardHeader
        icon={Gavel}
        tone="amber"
        title="قرارات الغياب والتأخير"
        description="«تطبيق» يعرض المبلغ المحسوب (أجر اليوم = الراتب ÷ 30، والتأخير بالدقيقة من بداية الدوام) وتكدر تعدّله قبل الخصم، و«تجاهل» يعفي الموظف"
      />
      <DataTable>
        <thead>
          <tr>
            <th>الموظف</th>
            <th>التاريخ</th>
            <th>المخالفة</th>
            <th>المدة</th>
            <th>الخصم (د.ع)</th>
            <th>السبب</th>
            <th className="!text-left">القرار</th>
          </tr>
        </thead>
        <tbody>
          {decisionsList.length === 0 ? (
            <TableEmpty colSpan={7}>لا توجد غيابات أو تأخيرات لهذه الفترة</TableEmpty>
          ) : (
            decisionsList.map((item) => {
              const key = decisionKey(item);
              const reason = selectedReasons[key] ?? item.reason;
              const busy = busyKey === key;
              return (
                <tr key={key}>
                  <td>
                    <div className="flex items-center gap-2.5 min-w-[180px]">
                      <Avatar name={item.employee.full_name} size="sm" />
                      <div>
                        <p className="font-bold text-white">{item.employee.full_name}</p>
                        <p className="text-[10px] text-slate-500">
                          {item.employee.departments?.name || 'بدون قسم'} · {item.time !== '-' ? `البصمة ${item.time}` : 'غياب كامل'}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td className="font-mono text-slate-400 whitespace-nowrap" dir="ltr">{item.date}</td>
                  <td>
                    <Badge tone={item.type === 'late' ? 'amber' : 'rose'}>{item.type === 'late' ? 'تأخير' : 'غياب'}</Badge>
                  </td>
                  <td className="whitespace-nowrap">{item.duration}</td>
                  <td>
                    {item.suggestedAmount > 0 ? (
                      <span className={`font-mono font-bold whitespace-nowrap ${item.deductionStatus === 'ignored' ? 'text-slate-500 line-through' : 'text-rose-300'}`}>
                        {Math.round(item.suggestedAmount).toLocaleString('en-US')}
                      </span>
                    ) : (
                      <span className="text-[11px] text-slate-500">يُحسب تلقائياً</span>
                    )}
                  </td>
                  <td>
                    <Input value={reason} onChange={(e) => onReasonChange(key, e.target.value)} list="decision-reasons"
                      className="h-8 min-w-[200px] text-xs" />
                  </td>
                  <td className="!text-left">
                    <div className="flex justify-end gap-1.5">
                      <Button
                        size="xs"
                        variant={item.deductionStatus === 'applied' ? 'success' : 'soft-success'}
                        disabled={busy}
                        onClick={() => onDecide(item, 'applied', reason)}
                      >
                        تطبيق
                      </Button>
                      <Button
                        size="xs"
                        variant={item.deductionStatus === 'ignored' ? 'secondary' : 'ghost'}
                        disabled={busy}
                        onClick={() => onDecide(item, 'ignored', reason)}
                      >
                        تجاهل
                      </Button>
                    </div>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </DataTable>
      {/* ملاحظات جاهزة تطلع بالحقل (مثل: نسي البصمة وهو مداوم) */}
      <datalist id="decision-reasons">
        {[...EXCUSE_REASONS, ...DEDUCT_REASONS].map((r) => <option key={r} value={r} />)}
      </datalist>
    </Card>
  );
}
