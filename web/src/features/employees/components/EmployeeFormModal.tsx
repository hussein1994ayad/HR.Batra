'use client';

import React, { useEffect, useState } from 'react';
import Image from 'next/image';
import toast from 'react-hot-toast';
import { Clock, Eye, EyeOff, Pencil, Save, Upload, UserPlus, X } from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { AmountInput, Field, Input, Modal, ModalFooter, Select, cn } from '@/components/ui';
import { emptyEmployeeForm, employeeToFormValues } from '../logic';
import type { BranchOption, EmployeeFormValues } from '../types';

function Thumb({ src, onRemove, highlight }: { src: string; onRemove: () => void; highlight?: boolean }) {
  return (
    <div className="relative group">
      <Image
        src={src}
        alt="مستند"
        width={64}
        height={64}
        unoptimized
        className={cn('w-16 h-16 object-cover rounded-xl border', highlight ? 'border-indigo-500/50' : 'border-slate-700')}
      />
      <button
        type="button"
        onClick={onRemove}
        aria-label="إزالة"
        className="absolute -top-2 -right-2 bg-rose-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity shadow-md cursor-pointer"
      >
        <X className="w-3 h-3" />
      </button>
    </div>
  );
}

function FileThumb({ file, onRemove }: { file: File; onRemove: () => void }) {
  const [url] = useState(() => URL.createObjectURL(file));
  useEffect(() => () => URL.revokeObjectURL(url), [url]);
  return <Thumb src={url} onRemove={onRemove} highlight />;
}

type Props = {
  /** null = إضافة موظف جديد */
  employee: Employee | null;
  branches: BranchOption[];
  saving: boolean;
  onClose: () => void;
  onSubmit: (values: EmployeeFormValues, keptDocuments: string[], newDocuments: File[]) => void;
};

/** إضافة موظف (حساب دخول عبر create_employee_secure) أو تعديل بياناته ومستمسكاته. */
export function EmployeeFormModal({ employee, branches, saving, onClose, onSubmit }: Props) {
  const isEdit = !!employee;
  const [form, setForm] = useState<EmployeeFormValues>(() => (employee ? employeeToFormValues(employee) : emptyEmployeeForm()));
  const [showPassword, setShowPassword] = useState(false);
  const [existingDocs, setExistingDocs] = useState<string[]>(employee?.document_urls ?? []);
  const [newDocs, setNewDocs] = useState<File[]>([]);
  const set = <K extends keyof EmployeeFormValues>(key: K, value: EmployeeFormValues[K]) => setForm((f) => ({ ...f, [key]: value }));

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.fullName.trim()) return void toast.error('يرجى إدخال اسم الموظف');
    if (!form.email.trim()) return void toast.error('يرجى إدخال البريد الإلكتروني');
    if (!isEdit && form.password.length < 6) return void toast.error('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
    onSubmit(form, existingDocs, newDocs);
  };

  return (
    <Modal
      title={isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد'}
      subtitle={isEdit ? employee?.full_name : 'ينشئ حساب دخول لتطبيق الموبايل ويسجل البيانات الوظيفية'}
      icon={isEdit ? Pencil : UserPlus}
      tone="brand"
      size="lg"
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-5">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Field label="الاسم الكامل">
            <Input required value={form.fullName} onChange={(e) => set('fullName', e.target.value)} placeholder="محمد علي عبد الحسين" />
          </Field>
          <Field label="البريد الإلكتروني (اسم الدخول)">
            <Input type="email" required value={form.email} onChange={(e) => set('email', e.target.value)} placeholder="name@company.com" dir="ltr" className="text-left" />
          </Field>
          <Field label="رقم الهاتف">
            <Input type="tel" value={form.phone} onChange={(e) => set('phone', e.target.value)} placeholder="077XXXXXXXX" dir="ltr" className="text-left" />
          </Field>
          <Field label={isEdit ? 'كلمة المرور' : 'كلمة المرور (6 أحرف فأكثر)'}>
            <div className="relative">
              <Input
                type={showPassword ? 'text' : 'password'}
                required={!isEdit}
                value={form.password}
                onChange={(e) => set('password', e.target.value)}
                placeholder="••••••••"
                dir="ltr"
                className="text-left pl-10"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                aria-label={showPassword ? 'إخفاء' : 'إظهار'}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 hover:text-white cursor-pointer"
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </Field>
          <Field label="الفرع">
            <Select required value={form.branchId} onChange={(e) => set('branchId', e.target.value)}>
              <option value="">اختر الفرع...</option>
              {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </Select>
          </Field>
          <Field label="الصلاحية">
            <Select value={form.role} onChange={(e) => set('role', e.target.value)}>
              <option value="employee">موظف</option>
              <option value="manager">مدير موارد</option>
              <option value="admin">مدير عام</option>
            </Select>
          </Field>
          <Field label="الراتب الأساسي الشهري (د.ع)">
            <AmountInput required value={form.monthlySalary} onValueChange={(v) => set('monthlySalary', v)} placeholder="1,500,000" />
          </Field>
          <Field label="تاريخ المباشرة بالعمل">
            <Input type="date" required value={form.joinDate} onChange={(e) => set('joinDate', e.target.value)} dir="ltr" />
          </Field>
        </div>

        {isEdit && (
          <div className="rounded-2xl border border-indigo-500/20 bg-indigo-500/5 p-4">
            <p className="text-xs font-bold text-indigo-200 mb-3 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" /> تغيير راتب مجدول (اختياري)
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="الراتب الجديد (د.ع)">
                <AmountInput value={form.futureSalary} onValueChange={(v) => set('futureSalary', v)} placeholder="مبلغ الراتب" />
              </Field>
              <Field label="يبدأ من تاريخ">
                <Input type="date" value={form.futureSalaryMonth} onChange={(e) => set('futureSalaryMonth', e.target.value)} dir="ltr" />
              </Field>
            </div>
          </div>
        )}

        <Field label="المستمسكات الثبوتية (اختياري)" hint="تُضغط الصور تلقائياً قبل الرفع. يمكنك حذف القديمة وإضافة جديدة.">
          <div className="flex flex-wrap gap-3">
            {existingDocs.map((url) => (
              <Thumb key={url} src={url} onRemove={() => setExistingDocs((prev) => prev.filter((u) => u !== url))} />
            ))}
            {newDocs.map((file, idx) => (
              <FileThumb key={`${file.name}_${idx}`} file={file} onRemove={() => setNewDocs((prev) => prev.filter((_, i) => i !== idx))} />
            ))}
            <label className="w-16 h-16 flex items-center justify-center border border-dashed border-slate-700 rounded-xl cursor-pointer hover:border-indigo-500 hover:bg-slate-800/50 transition-colors">
              <input
                type="file"
                multiple
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const files = e.target.files;
                  if (files) setNewDocs((prev) => [...prev, ...Array.from(files)]);
                  e.target.value = '';
                }}
              />
              <Upload className="w-5 h-5 text-slate-500" />
            </label>
          </div>
        </Field>

        <ModalFooter
          onCancel={onClose}
          loading={saving}
          submitLabel={isEdit ? 'حفظ التعديلات' : 'إضافة الموظف'}
          loadingLabel={isEdit ? 'جاري الحفظ...' : 'جاري إنشاء الحساب...'}
          submitIcon={isEdit ? Save : UserPlus}
        />
      </form>
    </Modal>
  );
}
