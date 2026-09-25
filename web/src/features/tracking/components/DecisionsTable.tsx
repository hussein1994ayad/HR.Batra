import { decisionKey } from '../logic';
import type { Decision } from '../types';

type Props = {
  decisionsList: Decision[];
  selectedAmounts: Record<string, string>;
  selectedReasons: Record<string, string>;
  onAmountChange: (key: string, value: string) => void;
  onReasonChange: (key: string, value: string) => void;
  onDecide: (item: Decision, status: 'applied' | 'ignored', reason: string, amount: number) => void;
};

/** قرارات الخصم: تطبيق أو تجاهل لكل غياب/تأخير، مع تعديل المبلغ والسبب. */
export function DecisionsTable({ decisionsList, selectedAmounts, selectedReasons, onAmountChange, onReasonChange, onDecide }: Props) {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h4 className="text-md font-bold text-white">إجراءات المخالفات وقرارات الخصم من الراتب</h4>
          <p className="text-[11px] text-slate-400">حدد «تطبيق» لتخصيم القيمة من صافي الراتب، أو «تجاهل» للعفو عن الموظف دون تأثر راتبه</p>
        </div>
      </div>

      <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
        <table className="w-full text-sm text-right">
          <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
            <tr>
              <th className="px-4 py-4 font-bold w-12 text-center">✓</th>
              <th className="px-4 py-4 font-bold">الموظف</th>
              <th className="px-4 py-4 font-bold">المدة</th>
              <th className="px-4 py-4 font-bold">نوع المخالفة</th>
              <th className="px-4 py-4 font-bold">الخصم (د.ع)</th>
              <th className="px-4 py-4 font-bold">السبب</th>
              <th className="px-4 py-4 font-bold text-center">القرار</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/60 bg-slate-950/30 text-xs">
            {decisionsList.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-4 py-12 text-center text-slate-500 text-xs">
                  لا توجد غيابات أو تأخيرات مرصودة للتاريخ المختار
                </td>
              </tr>
            ) : (
              decisionsList.map((item, idx) => {
                const rowKey = decisionKey(item);
                const currentReason = selectedReasons[rowKey] || item.reason;

                return (
                  <tr key={idx} className="hover:bg-slate-900/40 transition-colors">
                    <td className="px-4 py-4 text-center">
                      <span className="text-[10px] bg-slate-850 px-2 py-0.5 rounded text-slate-400 font-mono">
                        {idx + 1}
                      </span>
                    </td>
                    <td className="px-4 py-4">
                      <div className="flex flex-col">
                        <span className="font-bold text-white">{item.employee.full_name}</span>
                        <span className="text-[10px] text-slate-400">
                          {item.employee.departments?.name || 'بدون قسم'} • {item.time !== '-' ? `البصمة: ${item.time}` : 'غياب كامل اليوم'}
                        </span>
                      </div>
                    </td>
                    <td className="px-4 py-4 text-slate-300 font-bold font-mono">
                      {item.duration}
                    </td>
                    <td className="px-4 py-4">
                      <span className={`px-2.5 py-0.5 rounded-full text-[10px] font-bold ${
                        item.type === 'late' ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                      }`}>
                        {item.typeName}
                      </span>
                    </td>
                    <td className="px-4 py-4">
                      <input 
                        type="number"
                        value={selectedAmounts[rowKey] !== undefined ? selectedAmounts[rowKey] : (item.suggestedAmount || '')}
                        onChange={(e) => onAmountChange(rowKey, e.target.value)}
                        className="bg-slate-900 text-xs text-white border border-slate-700/60 rounded-xl px-2.5 py-1.5 outline-none w-24 mb-2"
                        placeholder="مبلغ الخصم"
                      />
                    </td>
                    <td className="px-4 py-4">
                      <input
                        type="text"
                        value={currentReason}
                        onChange={(e) => onReasonChange(rowKey, e.target.value)}
                        className="bg-slate-900 text-xs text-white border border-slate-700/60 rounded-xl px-2.5 py-1.5 outline-none w-full"
                        placeholder="اكتب سبب الخصم هنا..."
                      />
                    </td>
                    <td className="px-4 py-4 text-center">
                      <div className="flex items-center justify-center gap-2">
                        {/* Apply button */}
                        <button
                          onClick={() => {
                            const amt = Number(selectedAmounts[rowKey] !== undefined ? selectedAmounts[rowKey] : item.suggestedAmount) || 0;
                            onDecide(item, 'applied', currentReason, amt);
                          }}
                          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                            item.deductionStatus === 'applied'
                              ? 'bg-emerald-600 text-white shadow-md shadow-emerald-500/10'
                              : 'bg-slate-800 text-slate-400 hover:bg-emerald-600/20 hover:text-emerald-400 border border-slate-700'
                          }`}
                        >
                          تطبيق
                        </button>
                        
                        {/* Ignore button */}
                        <button
                          onClick={() => onDecide(item, 'ignored', currentReason, 0)}
                          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                            item.deductionStatus === 'ignored'
                              ? 'bg-rose-600 text-white shadow-md shadow-rose-500/10'
                              : 'bg-slate-800 text-slate-400 hover:bg-rose-600/20 hover:text-rose-400 border border-slate-700'
                          }`}
                        >
                          تجاهل
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
