'use client';

import React, { useState } from 'react';
import type { WorkSchedule } from '@/lib/db-types';
import { DEFAULT_SCHEDULE_FORM, formatTime12h, getDayNameAr, scheduleTargetName, toggleWorkDay } from '../logic';
import type { ScheduleForm, ScheduleScope, ScheduleTargets } from '../types';
import { Loader2, Clock, Trash2 } from 'lucide-react';

interface WorkSchedulesSectionProps {
  workSchedules: WorkSchedule[];
  branchesList: ScheduleTargets['branches'];
  departmentsList: ScheduleTargets['departments'];
  employeesList: ScheduleTargets['employees'];
  onAdd: (form: ScheduleForm) => Promise<boolean>;
  onDelete: (id: string) => void;
}

/** إضافة جداول الدوام (لفرع أو قسم أو موظف) وقائمة الجداول الحالية. */
export function WorkSchedulesSection({ workSchedules, branchesList, departmentsList, employeesList, onAdd, onDelete }: WorkSchedulesSectionProps) {
  const [schedName, setSchedName] = useState(DEFAULT_SCHEDULE_FORM.name);
  const [schedScope, setSchedScope] = useState<ScheduleScope>(DEFAULT_SCHEDULE_FORM.scope);
  const [schedTargetId, setSchedTargetId] = useState(DEFAULT_SCHEDULE_FORM.targetId);
  const [schedCheckIn, setSchedCheckIn] = useState(DEFAULT_SCHEDULE_FORM.checkIn);
  const [schedCheckOut, setSchedCheckOut] = useState(DEFAULT_SCHEDULE_FORM.checkOut);
  const [schedGrace, setSchedGrace] = useState(DEFAULT_SCHEDULE_FORM.grace);
  const [schedWorkDays, setSchedWorkDays] = useState<number[]>(DEFAULT_SCHEDULE_FORM.workDays);
  const [addingSchedule, setAddingSchedule] = useState(false);
  const targets = { branches: branchesList, departments: departmentsList, employees: employeesList };

  const handleAddSchedule = async (e: React.FormEvent) => {
    e.preventDefault();
    setAddingSchedule(true);
    const ok = await onAdd({
      name: schedName, scope: schedScope, targetId: schedTargetId,
      checkIn: schedCheckIn, checkOut: schedCheckOut, grace: schedGrace, workDays: schedWorkDays,
    });
    setAddingSchedule(false);
    if (ok) {
      setSchedName(DEFAULT_SCHEDULE_FORM.name);
      setSchedTargetId(DEFAULT_SCHEDULE_FORM.targetId);
      setSchedCheckIn(DEFAULT_SCHEDULE_FORM.checkIn);
      setSchedCheckOut(DEFAULT_SCHEDULE_FORM.checkOut);
      setSchedGrace(DEFAULT_SCHEDULE_FORM.grace);
      setSchedWorkDays(DEFAULT_SCHEDULE_FORM.workDays);
    }
  };

  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 mt-8">
      <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850 font-bold">
        <Clock className="w-5 h-5 text-teal-400" />
        <h4 className="text-sm font-extrabold text-white">إدارة جداول وأوقات العمل بالفروع والأقسام والموظفين 📅</h4>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Add Work Schedule Form */}
        <div className="lg:col-span-1 bg-slate-950/40 border border-slate-850 p-6 rounded-2xl space-y-4 text-right" dir="rtl">
          <h5 className="text-xs font-bold text-teal-400 mb-2">إضافة جدول دوام جديد:</h5>
          <form onSubmit={handleAddSchedule} className="space-y-4">
            <div>
              <label className="block text-[10px] text-slate-400 mb-1">اسم جدول الدوام</label>
              <input
                type="text"
                required
                placeholder="مثال: دوام فرع بغداد المعتاد"
                value={schedName}
                onChange={(e) => setSchedName(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
              />
            </div>

            <div>
              <label className="block text-[10px] text-slate-400 mb-1">نطاق تطبيق الجدول</label>
              <select
                value={schedScope}
                onChange={(e) => {
                  setSchedScope(e.target.value as ScheduleScope);
                  setSchedTargetId('');
                }}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
              >
                <option value="branch">🏢 تحديد حسب الفرع الجغرافي</option>
                <option value="department">📂 تحديد حسب القسم الإداري</option>
                <option value="employee">👤 تحديد لموظف معين بشكل مخصص</option>
              </select>
            </div>

            <div>
              <label className="block text-[10px] text-slate-400 mb-1 font-bold">الجهة المستهدفة بالفرع أو القسم</label>
              <select
                required
                value={schedTargetId}
                onChange={(e) => setSchedTargetId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none font-bold"
              >
                <option value="">-- اختر الجهة المحددة --</option>
                {schedScope === 'branch' && branchesList.map(b => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
                {schedScope === 'department' && departmentsList.map(d => (
                  <option key={d.id} value={d.id}>{d.name}</option>
                ))}
                {schedScope === 'employee' && employeesList.map(e => (
                  <option key={e.id} value={e.id}>{e.full_name}</option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-[10px] text-slate-400 mb-1">وقت الدخول المعتمد</label>
                <input
                  type="time"
                  required
                  value={schedCheckIn}
                  onChange={(e) => setSchedCheckIn(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                  dir="ltr"
                />
              </div>
              <div>
                <label className="block text-[10px] text-slate-400 mb-1">وقت الخروج المعتمد</label>
                <input
                  type="time"
                  required
                  value={schedCheckOut}
                  onChange={(e) => setSchedCheckOut(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                  dir="ltr"
                />
              </div>
            </div>

            <div>
              <label className="block text-[10px] text-slate-400 mb-1">فترة السماح للتأخير بالدقائق</label>
              <input
                type="number"
                required
                min={0}
                value={schedGrace}
                onChange={(e) => setSchedGrace(Number(e.target.value))}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono font-bold"
                dir="ltr"
              />
            </div>

            <div>
              <label className="block text-[10px] text-slate-400 mb-2 font-bold">أيام العمل الأسبوعية النشطة</label>
              <div className="grid grid-cols-3 gap-2 text-right">
                {[
                  { value: 6, label: 'السبت' },
                  { value: 0, label: 'الأحد' },
                  { value: 1, label: 'الاثنين' },
                  { value: 2, label: 'الثلاثاء' },
                  { value: 3, label: 'الأربعاء' },
                  { value: 4, label: 'الخميس' },
                  { value: 5, label: 'الجمعة' }
                ].map(day => {
                  const isChecked = schedWorkDays.includes(day.value);
                  return (
                    <label key={day.value} className="flex items-center gap-1.5 text-[10px] text-slate-300 cursor-pointer hover:text-white transition-colors">
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => setSchedWorkDays(toggleWorkDay(schedWorkDays, day.value))}
                        className="rounded border-slate-850 text-teal-600 focus:ring-teal-500 w-3.5 h-3.5"
                      />
                      <span>{day.label}</span>
                    </label>
                  );
                })}
              </div>
            </div>

            <button
              type="submit"
              disabled={addingSchedule}
              className="w-full flex items-center justify-center gap-1.5 py-2.5 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
            >
              {addingSchedule ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>حفظ جدول الدوام 💾</span>}
            </button>
          </form>
        </div>

        {/* Active Work Schedules List */}
        <div className="lg:col-span-2 space-y-4 text-right">
          <h5 className="text-xs font-bold text-slate-300 mb-2">جداول الدوام المسجلة بالنظام:</h5>
          {workSchedules.length === 0 ? (
            <div className="text-center p-8 bg-slate-950/20 border border-slate-850 rounded-2xl text-slate-500 text-xs">
              لا توجد أي جداول دوام مضافة بالنظام حالياً. سيقوم النظام باعتماد الدوام المعتاد (السبت-الخميس من 9ص إلى 5م).
            </div>
          ) : (
            <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
              <table className="w-full text-right border-collapse">
                <thead>
                  <tr className="bg-slate-950/80 text-slate-300 text-[10px] font-bold border-b border-slate-800/80">
                    <th className="p-3">اسم الجدول</th>
                    <th className="p-3">الجهة المطبقة</th>
                    <th className="p-3">الأوقات المعتمدة</th>
                    <th className="p-3">أيام الدوام</th>
                    <th className="p-3 text-left">الإجراءات</th>
                  </tr>
                </thead>
                <tbody>
                  {workSchedules.map((ws) => (
                    <tr key={ws.id} className="border-b border-slate-800/40 hover:bg-slate-900/20 text-xs transition-colors">
                      <td className="p-3 font-bold text-white">{ws.name}</td>
                      <td className="p-3 text-slate-300 font-medium">
                        {scheduleTargetName(ws, targets)}
                      </td>
                      <td className="p-3 font-mono text-[10px] text-teal-400">
                        {formatTime12h(ws.check_in_time)} - {formatTime12h(ws.check_out_time)}
                        <span className="text-slate-500 text-[9px] block">سماح: {ws.grace_period_minutes} دقيقة</span>
                      </td>
                      <td className="p-3 max-w-[150px] truncate" title={(ws.work_days || []).map((d: number) => getDayNameAr(d)).join('، ')}>
                        <span className="text-[10px] text-slate-450">
                          {(ws.work_days || []).map((d: number) => getDayNameAr(d)).join('، ')}
                        </span>
                      </td>
                      <td className="p-3 text-left">
                        <button
                          type="button"
                          onClick={() => onDelete(ws.id)}
                          className="p-2 bg-slate-850 hover:bg-rose-500/10 hover:text-rose-400 border border-slate-800 hover:border-rose-500/20 text-slate-400 rounded-xl transition-all cursor-pointer"
                          title="حذف الجدول"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
