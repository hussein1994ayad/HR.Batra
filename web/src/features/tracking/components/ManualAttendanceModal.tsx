'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Loader2, Save } from 'lucide-react';
import type { TrackedEmployee } from '../types';

type Props = {
  employees: TrackedEmployee[];
  defaultDate: string;
  saving: boolean;
  onClose: () => void;
  onSave: (entry: { employeeId: string; date: string; checkIn: string; checkOut: string }) => void;
};

/** تسجيل حضور وانصراف يدوي لموظف. */
export function ManualAttendanceModal({ employees, defaultDate, saving, onClose, onSave }: Props) {
  const [manualEmpId, setManualEmpId] = useState('');
  const [manualDate, setManualDate] = useState(defaultDate);
  const [manualCheckIn, setManualCheckIn] = useState('09:00');
  const [manualCheckOut, setManualCheckOut] = useState('17:00');

  const handleManualAttendanceSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!manualEmpId) {
      toast('الرجاء اختيار الموظف أولاً');
      return;
    }
    onSave({ employeeId: manualEmpId, date: manualDate, checkIn: manualCheckIn, checkOut: manualCheckOut });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl animate-glass">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-bold text-white">تسجيل حضور وانصراف يدوي ✍️</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
        </div>
        
        <form onSubmit={handleManualAttendanceSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">الموظف</label>
            <select
              required
              value={manualEmpId}
              onChange={(e) => setManualEmpId(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-xs focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all cursor-pointer"
            >
              <option value="">-- اختر الموظف --</option>
              {employees.map(emp => (
                <option key={emp.id} value={emp.id} className="bg-slate-900">{emp.full_name}</option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">تاريخ الدوام (YYYY-MM-DD)</label>
            <input 
              type="text" 
              value={manualDate}
              onChange={(e) => setManualDate(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all font-mono"
              required
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">وقت الدخول</label>
            <input 
              type="time" 
              value={manualCheckIn}
              onChange={(e) => setManualCheckIn(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">وقت الخروج</label>
            <input 
              type="time" 
              value={manualCheckOut}
              onChange={(e) => setManualCheckOut(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
            />
          </div>

          <button
            type="submit"
            disabled={saving}
            className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            <span>تسجيل الحضور اليدوي 🎯</span>
          </button>
        </form>
      </div>
    </div>
  );
}
