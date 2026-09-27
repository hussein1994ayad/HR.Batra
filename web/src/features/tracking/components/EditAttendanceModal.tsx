'use client';

import React, { useState } from 'react';
import { Pencil, Save } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { Field, Input, Modal, ModalFooter } from '@/components/ui';
import { formatTimeInputValue } from '../logic';

type Props = {
  record: AttendanceRecord;
  saving: boolean;
  onClose: () => void;
  onSave: (checkIn: string, checkOut: string) => void;
};

/** تعديل وقتي الدخول والخروج لسجل حضور. */
export function EditAttendanceModal({ record, saving, onClose, onSave }: Props) {
  const [checkIn, setCheckIn] = useState(formatTimeInputValue(record.check_in_time));
  const [checkOut, setCheckOut] = useState(formatTimeInputValue(record.check_out_time));

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    onSave(checkIn, checkOut);
  };

  return (
    <Modal
      title="تعديل سجل الحضور"
      subtitle={`${record.employees?.full_name ?? ''} · ${record.work_date}`}
      icon={Pencil}
      tone="indigo"
      size="sm"
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <Field label="وقت الدخول">
            <Input type="time" value={checkIn} onChange={(e) => setCheckIn(e.target.value)} dir="ltr" />
          </Field>
          <Field label="وقت الخروج">
            <Input type="time" value={checkOut} onChange={(e) => setCheckOut(e.target.value)} dir="ltr" />
          </Field>
        </div>
        <ModalFooter onCancel={onClose} loading={saving} submitLabel="حفظ التعديلات" submitIcon={Save} />
      </form>
    </Modal>
  );
}
