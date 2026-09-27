'use client';

import React, { useState } from 'react';
import { X } from 'lucide-react';
import { Field, Input, Modal, ModalFooter } from '@/components/ui';

/**
 * تأكيد رفض مع حقل سبب اختياري (يصل للموظف في إشعار القرار).
 * بديل window.prompt بنفس شكل نوافذ اللوحة.
 */
export function ReasonModal({
  title,
  message,
  confirmLabel,
  loading,
  onCancel,
  onConfirm,
}: {
  title: string;
  message?: React.ReactNode;
  confirmLabel: string;
  loading?: boolean;
  onCancel: () => void;
  onConfirm: (reason: string) => void;
}) {
  const [reason, setReason] = useState('');
  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    onConfirm(reason.trim());
  };
  return (
    <Modal title={title} icon={X} tone="rose" size="sm" onClose={onCancel}>
      <form onSubmit={submit} className="space-y-4">
        {message && <p className="text-xs text-slate-300 leading-relaxed">{message}</p>}
        <Field label="سبب الرفض (اختياري)">
          <Input autoFocus value={reason} onChange={(e) => setReason(e.target.value)} placeholder="يظهر للموظف في إشعار القرار" />
        </Field>
        <ModalFooter onCancel={onCancel} loading={loading} submitLabel={confirmLabel} variant="danger" />
      </form>
    </Modal>
  );
}
