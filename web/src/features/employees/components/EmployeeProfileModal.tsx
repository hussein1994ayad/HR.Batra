'use client';

import toast from 'react-hot-toast';
import { Download, Eye, FileImage, FileText, FolderOpen, Pencil, Share2 } from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { Avatar, Badge, Button, EmptyState, IconButton, Modal, type Tone } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { openStorageUrl, resolveStorageUrl } from '@/lib/signed-urls';

const ROLE_META: Record<string, { label: string; tone: Tone }> = {
  admin: { label: 'مدير عام', tone: 'rose' },
  manager: { label: 'مدير موارد', tone: 'amber' },
  employee: { label: 'موظف', tone: 'sky' },
};

type Props = {
  profileEmployee: Employee;
  onClose: () => void;
  onEdit: (emp: Employee) => void;
  onPreview: (url: string, title: string) => void;
};

function Detail({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl bg-slate-900/50 border border-slate-800/80 p-3">
      <p className="text-[10px] text-slate-500 mb-1">{label}</p>
      <div className="text-xs font-bold text-slate-100 break-all">{children}</div>
    </div>
  );
}

/** ملف الموظف الشامل مع قائمة الوثائق المرفوعة. */
export function EmployeeProfileModal({ profileEmployee: emp, onClose, onEdit, onPreview }: Props) {
  const docs = emp.document_urls ?? [];
  const role = ROLE_META[emp.role] ?? ROLE_META.employee;

  const copyLinks = async () => {
    try {
      // روابط موقّعة صالحة 7 أيام (الوثائق خاصة)
      const links = await Promise.all(docs.map((u) => resolveStorageUrl(u, 7 * 24 * 3600)));
      await navigator.clipboard.writeText(links.join('\n'));
      toast.success('تم نسخ روابط كافة الوثائق');
    } catch {
      toast.error('تعذر النسخ إلى الحافظة');
    }
  };

  return (
    <Modal title="ملف الموظف والوثائق" subtitle={emp.employee_code || undefined} icon={FolderOpen} tone="violet" size="lg" onClose={onClose}>
      <div className="flex items-center gap-3 mb-5">
        <Avatar name={emp.full_name} size="lg" />
        <div className="min-w-0">
          <p className="text-base font-extrabold text-white truncate">{emp.full_name}</p>
          <Badge tone={role.tone}>{role.label}</Badge>
        </div>
        <Button size="sm" variant="secondary" icon={Pencil} className="mr-auto" onClick={() => onEdit(emp)}>
          تعديل البيانات والمستمسكات
        </Button>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-6">
        <Detail label="البريد الإلكتروني"><span dir="ltr">{emp.email || '—'}</span></Detail>
        <Detail label="رقم الهاتف"><span dir="ltr">{emp.phone || '—'}</span></Detail>
        <Detail label="الفرع">{emp.branches?.name || '—'}</Detail>
        <Detail label="الراتب الأساسي">{formatIQD(emp.monthly_salary_iqd)}</Detail>
        <Detail label="قفل الهاتف">{emp.device_id_lock ? 'مقفل على جهاز' : 'غير مقيد'}</Detail>
        <Detail label="تاريخ المباشرة"><span dir="ltr">{emp.join_date || '—'}</span></Detail>
      </div>

      <div className="flex items-center justify-between mb-3">
        <h4 className="text-sm font-bold text-white flex items-center gap-2">
          <FolderOpen className="w-4 h-4 text-teal-300" /> المستمسكات المرفوعة <Badge tone="teal">{docs.length}</Badge>
        </h4>
        {docs.length > 0 && (
          <Button size="xs" variant="ghost" icon={Share2} onClick={copyLinks}>نسخ الروابط</Button>
        )}
      </div>

      {docs.length === 0 ? (
        <EmptyState icon={FolderOpen} title="لا توجد وثائق مرفوعة لهذا الموظف" />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-h-72 overflow-y-auto">
          {docs.map((url, idx) => {
            const isPdf = url.toLowerCase().includes('.pdf');
            const title = `وثيقة ${emp.full_name} #${idx + 1}`;
            return (
              <div key={url} className="flex items-center justify-between gap-3 p-3 rounded-2xl bg-slate-900/50 border border-slate-800/80">
                <div className="flex items-center gap-3 min-w-0">
                  <div className={`p-2.5 rounded-xl ${isPdf ? 'bg-rose-500/15 text-rose-300' : 'bg-teal-500/15 text-teal-300'}`}>
                    {isPdf ? <FileText className="w-5 h-5" /> : <FileImage className="w-5 h-5" />}
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs font-bold text-white truncate">وثيقة رسمية #{idx + 1}</p>
                    <p className="text-[10px] text-slate-500">{isPdf ? 'ملف PDF' : 'صورة مستمسك'}</p>
                  </div>
                </div>
                <div className="flex gap-1">
                  <IconButton icon={Eye} label="معاينة" tone="teal" onClick={() => onPreview(url, title)} />
                  <button
                    type="button"
                    onClick={() => openStorageUrl(url).catch(() => toast.error('تعذر فتح الوثيقة'))}
                    title="فتح وتحميل"
                    className="inline-flex items-center justify-center w-8 h-8 rounded-lg text-sky-300 hover:bg-sky-500/15 cursor-pointer"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Modal>
  );
}
