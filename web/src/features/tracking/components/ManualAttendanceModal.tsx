'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { UserPlus, Users } from 'lucide-react';
import { Field, Input, Modal, ModalFooter, Select } from '@/components/ui';
import { localDateStr } from '@/lib/format';
import type { TrackedEmployee } from '../types';

type Props = {
  employees: TrackedEmployee[];
  defaultDate: string;
  saving: boolean;
  onClose: () => void;
  onSave: (entry: { employeeId: string; date: string; checkIn: string; checkOut: string }) => void;
};

/** تسجيل حضور يدوي؛ يُحدَّث السجل إن كان للموظف بصمة في نفس اليوم. */
export function ManualAttendanceModal({ employees, defaultDate, saving, onClose, onSave }: Props) {
  const [employeeId, setEmployeeId] = useState('');
  const [date, setDate] = useState(defaultDate);
  const [checkIn, setCheckIn] = useState('09:00');
  const [checkOut, setCheckOut] = useState('17:00');

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!employeeId) {
      toast.error('الرجاء اختيار الموظف أولاً');
      return;
    }
    onSave({ employeeId, date, checkIn, checkOut });
  };

  return (
    <Modal title="تسجيل حضور يدوي" subtitle="يُحدَّث السجل إن كان للموظف بصمة في نفس اليوم" icon={UserPlus} tone="brand" size="sm" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="الموظف">
          <Select required value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
            <option value="">اختر الموظف...</option>
            {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.full_name}</option>)}
          </Select>
        </Field>
        <Field label="تاريخ الدوام">
          <Input type="date" required value={date} max={localDateStr()} onChange={(e) => setDate(e.target.value)} dir="ltr" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="وقت الدخول">
            <Input type="time" value={checkIn} onChange={(e) => setCheckIn(e.target.value)} dir="ltr" />
          </Field>
          <Field label="وقت الخروج">
            <Input type="time" value={checkOut} onChange={(e) => setCheckOut(e.target.value)} dir="ltr" />
          </Field>
        </div>
        <ModalFooter onCancel={onClose} loading={saving} submitLabel="تسجيل الحضور" submitIcon={Users} />
      </form>
    </Modal>
  );
}
