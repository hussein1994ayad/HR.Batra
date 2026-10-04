'use client';

// بث تعميم من الرئيسية: الجمهور (الكل / فرع / موظفون)، العنوان والنص، ومدة الظهور بالتطبيق
// (فارغ = بدون نهاية). الحفظ والإشعار بخطوة وحدة على السيرفر.

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Send } from 'lucide-react';
import { confetti } from '@/lib/lazy';
import { errorMessage } from '@/lib/format';
import { addDaysStr, getLocalDateStr } from '@/lib/dates';
import { Field, Input, Modal, ModalFooter, SearchInput, Select, SegmentedTabs, Textarea, cn } from '@/components/ui';
import { publishAnnouncement, type DashboardData } from '../api';
import type { DirectoryEmployee } from '../logic';

export function AnnouncementModal({
  branches,
  employees,
  onClose,
}: {
  branches: DashboardData['branches'];
  employees: DirectoryEmployee[];
  onClose: () => void;
}) {
  const [title, setTitle] = useState('');
  const [text, setText] = useState('');
  const today = getLocalDateStr();
  // مدة ظهور التعميم في التطبيق: من تاريخ إلى تاريخ (فارغ = بدون نهاية)
  const [startDate, setStartDate] = useState(today);
  const [endDate, setEndDate] = useState(() => addDaysStr(today, 6));
  const [targetType, setTargetType] = useState<'all' | 'branch' | 'employee'>('all');
  const [branchId, setBranchId] = useState('');
  const [employeeIds, setEmployeeIds] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [sending, setSending] = useState(false);

  const visibleEmployees = employees.filter((e) => (e.full_name || '').toLowerCase().includes(search.toLowerCase()));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!text.trim() || !title.trim()) return;
    if (targetType === 'branch' && !branchId) return void toast.error('يرجى اختيار الفرع المستهدف أولاً');
    if (targetType === 'employee' && employeeIds.length === 0) return void toast.error('يرجى اختيار موظف واحد على الأقل');
    if (endDate && endDate < startDate) return void toast.error('تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية');
    setSending(true);
    try {
      // يحفظ التعميم بمدته وجمهوره ويُشعر المستهدفين في خطوة واحدة؛ يختفي من التطبيق بعد مدته
      const sent = await publishAnnouncement({
        p_title: title.trim(),
        p_content: text.trim(),
        p_starts_at: startDate === today ? null : new Date(`${startDate}T00:00:00`).toISOString(),
        p_ends_at: endDate ? new Date(`${endDate}T23:59:59`).toISOString() : null,
        p_target: targetType === 'employee' ? 'employees' : targetType,
        p_branch_id: targetType === 'branch' ? branchId : null,
        p_employee_ids: targetType === 'employee' ? employeeIds : null,
      });

      confetti({ particleCount: 80, spread: 60, origin: { y: 0.8 } });
      toast.success(`تم نشر التعميم ووصل إشعاره إلى ${sent ?? 0} موظف`);
      onClose();
    } catch (err) {
      toast.error(`فشل إرسال التعميم: ${errorMessage(err)}`);
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal title="بث تعميم إداري" subtitle="يصل التعميم فوراً كإشعار على هواتف الموظفين المستهدفين" icon={Send} tone="brand" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="المستلمون">
          <SegmentedTabs
            value={targetType}
            onChange={setTargetType}
            className="w-full"
            options={[
              { value: 'all', label: 'الكل' },
              { value: 'branch', label: 'فرع معين' },
              { value: 'employee', label: 'موظفون محددون', count: employeeIds.length || undefined },
            ]}
          />
        </Field>

        {targetType === 'branch' && (
          <Field label="الفرع المستهدف">
            <Select value={branchId} onChange={(e) => setBranchId(e.target.value)} required>
              <option value="">اختر الفرع...</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        {targetType === 'employee' && (
          <Field label={`الموظفون المستهدفون (${employeeIds.length} محدد)`}>
            <SearchInput value={search} onChange={setSearch} placeholder="ابحث باسم الموظف..." className="mb-2" />
            <div className="max-h-[180px] overflow-y-auto border border-slate-800 rounded-xl p-1.5 bg-slate-950/50">
              {visibleEmployees.map((emp) => {
                const checked = employeeIds.includes(emp.id);
                return (
                  <label
                    key={emp.id}
                    className={cn(
                      'flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-xs cursor-pointer transition-colors',
                      checked ? 'bg-indigo-500/10 text-white' : 'text-slate-300 hover:bg-slate-800/50',
                    )}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() =>
                        setEmployeeIds((prev) => (checked ? prev.filter((id) => id !== emp.id) : [...prev, emp.id]))
                      }
                      className="w-4 h-4 rounded"
                    />
                    {emp.full_name}
                  </label>
                );
              })}
            </div>
          </Field>
        )}

        <Field label="عنوان التعميم">
          <Input value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={80} placeholder="مثال: عطلة رسمية يوم الخميس" />
        </Field>

        <Field label="نص التعميم">
          <Textarea value={text} onChange={(e) => setText(e.target.value)} required rows={4} placeholder="اكتب نص التعميم هنا..." />
        </Field>

        <Field label="مدة الظهور في التطبيق" hint="يظهر في قسم التعاميم خلال هذه المدة ثم يختفي تلقائياً. اترك تاريخ الانتهاء فارغاً ليبقى بدون نهاية.">
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="block text-[11px] text-slate-500 mb-1">من</span>
              <Input type="date" value={startDate} min={today} onChange={(e) => setStartDate(e.target.value)} required dir="ltr" className="text-left" />
            </label>
            <label className="block">
              <span className="block text-[11px] text-slate-500 mb-1">إلى</span>
              <Input type="date" value={endDate} min={startDate} onChange={(e) => setEndDate(e.target.value)} dir="ltr" className="text-left" />
            </label>
          </div>
          <div className="flex flex-wrap gap-1.5 mt-2">
            {[
              { label: 'يوم', days: 0 },
              { label: '3 أيام', days: 2 },
              { label: 'أسبوع', days: 6 },
              { label: 'شهر', days: 29 },
            ].map((d) => (
              <button
                key={d.label}
                type="button"
                onClick={() => setEndDate(addDaysStr(startDate, d.days))}
                className={cn(
                  'h-7 px-3 rounded-lg text-[11px] font-bold border cursor-pointer transition-colors',
                  endDate === addDaysStr(startDate, d.days)
                    ? 'bg-indigo-500/15 border-indigo-500/40 text-indigo-200'
                    : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200',
                )}
              >
                {d.label}
              </button>
            ))}
            <button
              type="button"
              onClick={() => setEndDate('')}
              className={cn(
                'h-7 px-3 rounded-lg text-[11px] font-bold border cursor-pointer transition-colors',
                endDate === '' ? 'bg-indigo-500/15 border-indigo-500/40 text-indigo-200' : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200',
              )}
            >
              بدون نهاية
            </button>
          </div>
        </Field>

        <ModalFooter onCancel={onClose} loading={sending} submitLabel="نشر التعميم" loadingLabel="جاري النشر..." submitIcon={Send} />
      </form>
    </Modal>
  );
}
