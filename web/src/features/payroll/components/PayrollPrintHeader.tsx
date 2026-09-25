type Props = {
  currentMonthName: string;
  currentYearVal: string;
  startDate: string;
  endDate: string;
  branchLabel: string;
};

/** ترويسة كشف الرواتب عند الطباعة فقط. */
export function PayrollPrintHeader({ currentMonthName, currentYearVal, startDate, endDate, branchLabel }: Props) {
  return (
    <>
      {/* Print-Only Header Block */}
      <div className="hidden print:block text-slate-900 text-right p-6 border-b-2 border-slate-900 mb-8 font-sans" dir="rtl">
        <div className="flex justify-between items-start mb-6">
          <div>
            <h1 className="text-2xl font-black mb-1">قسم ادارة موظفين شركة بترى</h1>
            <p className="text-xs text-slate-500 font-bold">كشف رواتب الموظفين التفصيلي الشهري</p>
          </div>
          <div className="text-left font-mono text-[10px]">
            <p>تاريخ الطباعة: {new Date().toLocaleDateString('ar-IQ')}</p>
            <p>الوقت: {new Date().toLocaleTimeString('ar-IQ')}</p>
          </div>
        </div>
        
        <div className="grid grid-cols-3 gap-4 bg-slate-50 p-4 rounded-2xl border border-slate-200 text-xs mb-4">
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الشهر والسنة:</span>
            <span className="font-black text-sm text-slate-800">
              {currentMonthName} - {currentYearVal}
            </span>
          </div>
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الفترة المالية المحتسبة:</span>
            <span className="font-black text-sm text-slate-800 font-mono">
              {startDate} إلى {endDate}
            </span>
          </div>
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الفرع المالي:</span>
            <span className="font-black text-sm text-slate-800">
              {branchLabel}
            </span>
          </div>
        </div>
      </div>
    </>
  );
}
