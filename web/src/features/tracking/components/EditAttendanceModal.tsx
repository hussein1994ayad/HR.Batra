'use client';

import React, { useState } from 'react';
import { Loader2, Save } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { formatTimeInputValue } from '../logic';

type Props = {
  record: AttendanceRecord;
  saving: boolean;
  onClose: () => void;
  onSave: (checkIn: string, checkOut: string) => void;
};

/** تعديل وقت الدخول والخروج لسجل حضور. */
export function EditAttendanceModal({ record: editingRecord, saving, onClose, onSave }: Props) {
  const [editCheckIn, setEditCheckIn] = useState(formatTimeInputValue(editingRecord.check_in_time));
  const [editCheckOut, setEditCheckOut] = useState(formatTimeInputValue(editingRecord.check_out_time));

  const handleUpdateTimes = (e: React.FormEvent) => {
    e.preventDefault();
    onSave(editCheckIn, editCheckOut);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-bold text-white">تعديل سجل الحضور</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
        </div>
        
        <form onSubmit={handleUpdateTimes} className="space-y-4">
          <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
            <strong>الموظف:</strong> {editingRecord.employees?.full_name} <br/>
            <strong>التاريخ:</strong> {editingRecord.work_date}
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">وقت تسجيل الدخول</label>
            <input 
              type="time" 
              value={editCheckIn}
              onChange={(e) => setEditCheckIn(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">وقت تسجيل الخروج</label>
            <input 
              type="time" 
              value={editCheckOut}
              onChange={(e) => setEditCheckOut(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
            />
          </div>

          <button
            type="submit"
            disabled={saving}
            className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            <span>حفظ التعديلات</span>
          </button>
        </form>
      </div>
    </div>
  );
}
