import { Archive, Banknote, Calendar as CalendarIcon, Clock } from 'lucide-react';

type Props = {
  isMonthArchived: boolean;
  currentMonthVal: string;
  currentYearVal: string;
  startDate: string;
  endDate: string;
  totalNetSalaries: number;
  onMonthChange: (month: string) => void;
};

/** العنوان واختيار الشهر والسنة والفترة المالية وصافي الرواتب. */
export function PayrollHeader({
  isMonthArchived, currentMonthVal, currentYearVal, startDate, endDate, totalNetSalaries, onMonthChange,
}: Props) {
  return (
    <>
      {/* Header & Stats */}
      <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col lg:flex-row items-start lg:items-center justify-between gap-6 print:hidden">
        <div>
          <h3 className="text-xl font-extrabold text-white flex items-center gap-2 mb-2">
            <Banknote className="w-6 h-6 text-teal-400" />
            <span>نظام الرواتب والدوام الذكي (Payroll Hub)</span>
            {isMonthArchived && (
              <span className="flex items-center gap-1.5 px-3 py-1 bg-purple-500/20 border border-purple-500/40 text-purple-300 rounded-full font-bold text-xs select-none">
                <Archive className="w-3.5 h-3.5" />
                <span>مؤرشف ومغلق مالياً 📦</span>
              </span>
            )}
          </h3>
          <p className="text-xs text-slate-400">احتساب فوري للأجور والخصومات التلقائية للغيابات وأنصاف الأيام بناءً على البصمة الجغرافية</p>
        </div>

        <div className="flex flex-wrap items-center gap-3 bg-slate-950/50 p-2 rounded-2xl border border-slate-800/50">
          {/* Select Month Dropdown */}
          <div className="flex flex-col gap-1 px-2">
            <span className="text-[9px] text-slate-400 font-bold">الشهر</span>
            <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 hover:border-teal-500/50 transition-colors">
              <CalendarIcon className="w-3.5 h-3.5 text-teal-400" />
              <select
                value={currentMonthVal}
                onChange={(e) => {
                  const newMonth = e.target.value;
                  onMonthChange(`${currentYearVal}-${newMonth}`);
                }}
                className="bg-transparent border-none text-white text-[11px] outline-none cursor-pointer font-bold select-none pr-1 focus:ring-0"
              >
                <option value="01" className="bg-slate-900 text-white">1 - كانون الثاني (يناير)</option>
                <option value="02" className="bg-slate-900 text-white">2 - شباط (فبراير)</option>
                <option value="03" className="bg-slate-900 text-white">3 - آذار (مارس)</option>
                <option value="04" className="bg-slate-900 text-white">4 - نيسان (أبريل)</option>
                <option value="05" className="bg-slate-900 text-white">5 - أيار (مايو)</option>
                <option value="06" className="bg-slate-900 text-white">6 - حزيران (يونيو)</option>
                <option value="07" className="bg-slate-900 text-white">7 - تموز (يوليو)</option>
                <option value="08" className="bg-slate-900 text-white">8 - آب (أغسطس)</option>
                <option value="09" className="bg-slate-900 text-white">9 - أيلول (سبتمبر)</option>
                <option value="10" className="bg-slate-900 text-white">10 - تشرين الأول (أكتوبر)</option>
                <option value="11" className="bg-slate-900 text-white">11 - تشرين الثاني (نوفمبر)</option>
                <option value="12" className="bg-slate-900 text-white">12 - كانون الأول (ديسمبر)</option>
              </select>
            </div>
          </div>

          {/* Select Year Dropdown */}
          <div className="flex flex-col gap-1 px-2 border-r border-slate-800/80">
            <span className="text-[9px] text-slate-400 font-bold">السنة</span>
            <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 hover:border-teal-500/50 transition-colors">
              <CalendarIcon className="w-3.5 h-3.5 text-teal-400" />
              <select
                value={currentYearVal}
                onChange={(e) => {
                  const newYear = e.target.value;
                  onMonthChange(`${newYear}-${currentMonthVal}`);
                }}
                className="bg-transparent border-none text-white text-[11px] outline-none cursor-pointer font-bold select-none focus:ring-0"
              >
                {Array.from({ length: 9 }, (_, i) => 2024 + i).map(year => (
                  <option key={year} value={year.toString()} className="bg-slate-900 text-white">
                    {year}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Calculated Date Range (Read-Only Info Badge) */}
          <div className="flex flex-col gap-1 px-3 border-r border-slate-800/80 justify-center">
            <span className="text-[9px] text-slate-400 font-bold">الفترة المالية المحتسبة تلقائياً</span>
            <div className="text-[11px] text-teal-300 font-extrabold font-mono bg-teal-950/20 border border-teal-500/15 px-3 py-1.5 rounded-xl flex items-center gap-1.5 select-none">
              <Clock className="w-3 h-3 text-teal-400" />
              <span>{startDate}</span>
              <span className="text-slate-500">←</span>
              <span>{endDate}</span>
            </div>
          </div>

          <div className="flex flex-col items-end px-4 py-1 border-r border-slate-800/80">
            <span className="text-[9px] text-slate-400 font-bold">صافي تكلفة الرواتب المرصودة</span>
            <span className="text-md font-black text-emerald-400">{totalNetSalaries.toLocaleString()} <span className="text-[10px] font-bold text-slate-400">د.ع</span></span>
          </div>
        </div>
      </div>
    </>
  );
}
