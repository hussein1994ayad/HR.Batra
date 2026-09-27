/** خانات التوقيع أسفل كشف الرواتب عند الطباعة فقط. */
export function PayrollPrintSignatures() {
  return (
    <>
      {/* Print-Only Signature Block */}
      <div className="hidden print:block mt-16 text-slate-900 text-right font-sans" dir="rtl">
        <div className="grid grid-cols-3 gap-8 text-center text-xs">
          <div className="flex flex-col items-center">
            <span className="font-bold text-slate-600 mb-12">توقيع المحاسب المالي</span>
            <div className="w-40 border-b border-slate-400"></div>
          </div>
          <div className="flex flex-col items-center">
            <span className="font-bold text-slate-600 mb-12">توقيع مدير الموارد البشرية</span>
            <div className="w-40 border-b border-slate-400"></div>
          </div>
          <div className="flex flex-col items-center">
            <span className="font-bold text-slate-600 mb-12">اعتماد الإدارة العامة</span>
            <div className="w-40 border-b border-slate-400"></div>
          </div>
        </div>
      </div>
    </>
  );
}
