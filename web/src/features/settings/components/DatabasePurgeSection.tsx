'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { ARABIC_MONTH_NAMES } from '../logic';
import type { PurgeOptions } from '../types';
import { ShieldAlert, Loader2, Trash2 } from 'lucide-react';

interface DatabasePurgeSectionProps {
  onPurge: (options: PurgeOptions) => Promise<boolean>;
}

/** أداة حذف بيانات شهر قديم (بعد اعتماد رواتبه) مع نافذة تأكيد. */
export function DatabasePurgeSection({ onPurge }: DatabasePurgeSectionProps) {
  const [purgeMonth, setPurgeMonth] = useState<number>(() => new Date().getMonth() + 1);
  const [purgeYear, setPurgeYear] = useState<number>(() => new Date().getFullYear());
  const [purgeNotifications, setPurgeNotifications] = useState(false);
  const [purgeTracking, setPurgeTracking] = useState(false);
  const [purgeAbsences, setPurgeAbsences] = useState(false);
  const [isPurgeModalOpen, setIsPurgeModalOpen] = useState(false);
  const [purging, setPurging] = useState(false);
  const [confirmCheckbox, setConfirmCheckbox] = useState(false);
  const [purgeYears] = useState(() => {
    const last = new Date().getFullYear() + 1;
    return Array.from({ length: last - 2024 + 1 }, (_, i) => 2024 + i);
  });

  const handlePurgeClick = () => {
    if (!purgeNotifications && !purgeTracking && !purgeAbsences) {
      toast.error('يرجى تحديد فئة واحدة على الأقل لحذفها');
      return;
    }
    setConfirmCheckbox(false);
    setIsPurgeModalOpen(true);
  };

  const handleExecutePurge = async () => {
    if (!confirmCheckbox) {
      toast.error('يرجى تأكيد الإقرار بالمسؤولية أولاً');
      return;
    }
    setPurging(true);
    const ok = await onPurge({
      year: purgeYear, month: purgeMonth,
      notifications: purgeNotifications, tracking: purgeTracking, absences: purgeAbsences,
    });
    setPurging(false);
    if (ok) {
      setPurgeNotifications(false);
      setPurgeTracking(false);
      setPurgeAbsences(false);
      setIsPurgeModalOpen(false);
    }
  };

  return (
    <>
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 mt-8 text-right font-medium" dir="rtl">
        <div className="flex items-center gap-2 text-rose-450 pb-3 border-b border-slate-850 font-bold">
          <Trash2 className="w-5 h-5 text-rose-500 animate-pulse" />
          <h4 className="text-sm font-extrabold text-white">أداة تنظيف وتوفير مساحة قاعدة البيانات 🧹 (حذف يدوي للبيانات القديمة)</h4>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Select month, year, and categories */}
          <div className="lg:col-span-2 space-y-6">
            <p className="text-xs text-slate-400 leading-relaxed">
              تتيح لك هذه الأداة تفريغ البيانات القديمة يدوياً من قاعدة بيانات Supabase لتجنب امتلاء المساحة المجانية. <strong className="text-amber-400">شرط أساسي:</strong> لا يمكن تنظيف أي بيانات لشهر معين إلا بعد اعتماد ونشر رواتب جميع الموظفين لذلك الشهر، لضمان تجميد الاستقطاعات والسلف والبيانات المالية بالكامل.
            </p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-xs text-slate-400 mb-2 font-bold">اختر الشهر المحدد للحذف:</label>
                <select
                  value={purgeMonth}
                  onChange={(e) => setPurgeMonth(Number(e.target.value))}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-rose-500 rounded-xl p-3 text-xs text-white outline-none font-bold"
                >
                  {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((m) => (
                    <option key={m} value={m}>
                      الشهر {m} ({ARABIC_MONTH_NAMES[m - 1]})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-2 font-bold">اختر السنة المحددة للحذف:</label>
                <select
                  value={purgeYear}
                  onChange={(e) => setPurgeYear(Number(e.target.value))}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-rose-500 rounded-xl p-3 text-xs text-white outline-none font-bold"
                >
                  {purgeYears.map((y) => (
                    <option key={y} value={y}>السنة {y}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="space-y-4">
              <label className="block text-xs text-slate-350 font-bold mb-2">حدد الفئات التي ترغب في مسحها وتنظيفها من السيرفر:</label>
              
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {/* Checkbox 1: Notifications */}
                <label className={`flex items-start gap-3 p-4 rounded-2xl border transition-all cursor-pointer ${
                  purgeNotifications 
                    ? 'bg-rose-950/10 border-rose-500/40 text-white' 
                    : 'bg-slate-950/40 border-slate-850 text-slate-300 hover:border-slate-700'
                }`}>
                  <input
                    type="checkbox"
                    checked={purgeNotifications}
                    onChange={(e) => setPurgeNotifications(e.target.checked)}
                    className="mt-0.5 rounded border-slate-800 text-rose-600 focus:ring-rose-500 w-4.5 h-4.5"
                  />
                  <div>
                    <span className="block text-xs font-bold">حذف الإشعارات</span>
                    <span className="block text-[10px] text-slate-500 mt-1">تفريغ كافة إشعارات النظام والتنبيهات الموجهة للموظفين.</span>
                  </div>
                </label>

                {/* Checkbox 2: Location Tracking */}
                <label className={`flex items-start gap-3 p-4 rounded-2xl border transition-all cursor-pointer ${
                  purgeTracking 
                    ? 'bg-rose-950/10 border-rose-500/40 text-white' 
                    : 'bg-slate-950/40 border-slate-850 text-slate-300 hover:border-slate-700'
                }`}>
                  <input
                    type="checkbox"
                    checked={purgeTracking}
                    onChange={(e) => setPurgeTracking(e.target.checked)}
                    className="mt-0.5 rounded border-slate-800 text-rose-600 focus:ring-rose-500 w-4.5 h-4.5"
                  />
                  <div>
                    <span className="block text-xs font-bold">حذف سجلات الحركة</span>
                    <span className="block text-[10px] text-slate-500 mt-1">مسح إحداثيات الـ GPS والوقفات ومخالفات السياج الجغرافي (تأخذ أكبر مساحة).</span>
                  </div>
                </label>

                {/* Checkbox 3: Absences */}
                <label className={`flex items-start gap-3 p-4 rounded-2xl border transition-all cursor-pointer ${
                  purgeAbsences 
                    ? 'bg-rose-950/10 border-rose-500/40 text-white' 
                    : 'bg-slate-950/40 border-slate-850 text-slate-300 hover:border-slate-700'
                }`}>
                  <input
                    type="checkbox"
                    checked={purgeAbsences}
                    onChange={(e) => setPurgeAbsences(e.target.checked)}
                    className="mt-0.5 rounded border-slate-800 text-rose-600 focus:ring-rose-500 w-4.5 h-4.5"
                  />
                  <div>
                    <span className="block text-xs font-bold">حذف سجلات الحضور والغياب</span>
                    <span className="block text-[10px] text-slate-500 mt-1">مسح كافة سجلات الدوام (حاضر، غائب، متأخر، نصف يوم) لهذا الشهر. البيانات المالية مجمدة داخل كشوف الرواتب المعتمدة.</span>
                  </div>
                </label>
              </div>
            </div>
          </div>

          {/* Danger Zone Notice & Button */}
          <div className="lg:col-span-1 bg-slate-950/50 border border-slate-850/80 p-6 rounded-3xl flex flex-col justify-between gap-6">
            <div className="space-y-4">
              <span className="text-xs font-bold text-amber-500 flex items-center gap-1.5">
                <ShieldAlert className="w-4 h-4 text-amber-500" />
                <span>منطقة الخطر والتعليمات الهامة ⚠️</span>
              </span>
              <ul className="text-[10px] text-slate-400 space-y-2 list-disc list-inside leading-relaxed">
                <li>المسح نهائي ولا يمكن التراجع عنه.</li>
                <li>حذف سجلات التتبع والحضور يوفر أكبر مساحة تخزينية.</li>
                <li><strong className="text-amber-400">قفل مالي ذكي:</strong> لا يمكن حذف أي بيانات لشهر محدد ما لم يتم اعتماد ونشر رواتب جميع الموظفين النشطين لذلك الشهر — لحماية الاستقطاعات والسلف والخصومات من الضياع.</li>
              </ul>
            </div>

            <button
              type="button"
              onClick={handlePurgeClick}
              className="w-full flex items-center justify-center gap-2 py-3 px-4 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-rose-500/10 cursor-pointer active:scale-95"
            >
              <Trash2 className="w-4 h-4" />
              <span>تصفية وتنظيف البيانات المحددة 🧹</span>
            </button>
          </div>
        </div>
      </div>

      {isPurgeModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/85 backdrop-blur-sm p-4 text-right" dir="rtl">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl max-w-md w-full p-6 shadow-2xl space-y-6 animate-in fade-in zoom-in-95 duration-150">
            
            <div className="flex items-center gap-3 text-rose-500 pb-3 border-b border-slate-800">
              <ShieldAlert className="w-6 h-6 text-rose-500 animate-bounce" />
              <div>
                <h4 className="text-sm font-extrabold text-white">تأكيد الحذف النهائي والتصفية ⚠️</h4>
                <p className="text-[10px] text-slate-400 mt-1">هل أنت متأكد من رغبتك في مسح البيانات المختارة؟</p>
              </div>
            </div>

            <div className="space-y-4 text-xs leading-relaxed text-slate-350 bg-slate-950/50 p-4 border border-slate-850 rounded-2xl">
              <p>سيقوم النظام بحذف البيانات الخاصة بـ <strong className="text-white">الشهر {purgeMonth} / {purgeYear}</strong> للفئات التالية:</p>
              <ul className="list-disc list-inside space-y-2 text-[11px] text-rose-450 pr-4">
                {purgeNotifications && <li>🗑️ كافة الإشعارات والتنبيهات الموجهة للموظفين.</li>}
                {purgeTracking && <li>🗑️ سجلات المواقع GPS، الوقفات، ومخالفات السياج الجغرافي.</li>}
                {purgeAbsences && <li>🗑️ كافة سجلات الحضور والغياب والتأخير (حاضر، غائب، متأخر، نصف يوم).</li>}
              </ul>
              <p className="text-amber-500 text-[10px] border-t border-slate-850 pt-2 font-bold leading-normal">
                ⚠️ قفل مالي ذكي: لن تتم العملية إلا إذا كانت رواتب شهر {purgeMonth}/{purgeYear} معتمدة ومنشورة لكل الموظفين النشطين. هذا يضمن أن الاستقطاعات والسلف والخصومات مجمدة داخل كشوف الرواتب ولن تتأثر.
              </p>
            </div>

            <label className="flex items-start gap-3 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={confirmCheckbox}
                onChange={(e) => setConfirmCheckbox(e.target.checked)}
                className="mt-0.5 rounded border-slate-800 text-rose-650 focus:ring-rose-500 w-4 h-4"
              />
              <span className="text-[11px] text-slate-400 leading-relaxed font-bold">
                أقر وأوافق على الحذف النهائي للبيانات المحددة وأتحمل المسؤولية كاملة.
              </span>
            </label>

            <div className="flex gap-4">
              <button
                type="button"
                disabled={purging || !confirmCheckbox}
                onClick={handleExecutePurge}
                className={`flex-1 flex items-center justify-center gap-2 py-3 rounded-xl text-xs font-bold transition-all shadow-md ${
                  confirmCheckbox && !purging
                    ? 'bg-rose-600 hover:bg-rose-500 text-white shadow-rose-500/10 cursor-pointer active:scale-95'
                    : 'bg-slate-800 text-slate-500 border border-slate-750 cursor-not-allowed'
                }`}
              >
                {purging ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>جاري تصفية البيانات...</span>
                  </>
                ) : (
                  <>
                    <Trash2 className="w-4 h-4" />
                    <span>نعم، حذف نهائي 🗑️</span>
                  </>
                )}
              </button>

              <button
                type="button"
                disabled={purging}
                onClick={() => setIsPurgeModalOpen(false)}
                className="px-6 py-3 bg-slate-800 hover:bg-slate-750 border border-slate-700 text-slate-300 rounded-xl text-xs font-bold transition-all cursor-pointer"
              >
                إلغاء
              </button>
            </div>

          </div>
        </div>
      )}
    </>
  );
}
