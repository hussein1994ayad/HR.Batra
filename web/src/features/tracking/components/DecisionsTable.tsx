import { Gavel } from 'lucide-react';
import { AmountInput, Avatar, Badge, Button, Card, CardHeader, DataTable, Input, TableEmpty } from '@/components/ui';
import { decisionKey } from '../logic';
import type { Decision } from '../types';

type Props = {
  decisionsList: Decision[];
  selectedAmounts: Record<string, string>;
  selectedReasons: Record<string, string>;
  busyKey?: string | null;
  onAmountChange: (key: string, value: string) => void;
  onReasonChange: (key: string, value: string) => void;
  onDecide: (item: Decision, status: 'applied' | 'ignored', reason: string, amount: number) => void;
};

/** قرارات الخصم أو الإعفاء لكل غياب وتأخير في الفترة. */
export function DecisionsTable({ decisionsList, selectedAmounts, selectedReasons, busyKey, onAmountChange, onReasonChange, onDecide }: Props) {
  return (
    <Card>
      <CardHeader
        icon={Gavel}
        tone="amber"
        title="قرارات الغياب والتأخير"
        description="«تطبيق» يخصم المبلغ من صافي الراتب، و«تجاهل» يعفي الموظف دون التأثير على راتبه"
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
              const amount = selectedAmounts[key] !== undefined ? Number(selectedAmounts[key]) || 0 : item.suggestedAmount;
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
                    <AmountInput value={amount} onValueChange={(v) => onAmountChange(key, String(v))} className="h-8 w-28 text-xs" />
                  </td>
                  <td>
                    <Input value={reason} onChange={(e) => onReasonChange(key, e.target.value)} className="h-8 min-w-[200px] text-xs" />
                  </td>
                  <td className="!text-left">
                    <div className="flex justify-end gap-1.5">
                      <Button
                        size="xs"
                        variant={item.deductionStatus === 'applied' ? 'success' : 'soft-success'}
                        disabled={busy}
                        onClick={() => onDecide(item, 'applied', reason, amount)}
                      >
                        تطبيق
                      </Button>
                      <Button
                        size="xs"
                        variant={item.deductionStatus === 'ignored' ? 'secondary' : 'ghost'}
                        disabled={busy}
                        onClick={() => onDecide(item, 'ignored', reason, 0)}
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
    </Card>
  );
}
