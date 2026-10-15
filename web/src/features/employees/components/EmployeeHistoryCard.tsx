'use client';

// سجل الموظف بالتواريخ (تدقيق 14/10 FEATURE-001): باشر، انتقل من فرع لفرع، ترك، رجع.

import { History } from 'lucide-react';
import { useQuery } from '@/lib/useQuery';
import { arabicDate } from '@/lib/dates';
import { Badge, type Tone } from '@/components/ui';
import { fetchEmployeeHistory } from '../api';
import type { EmployeeHistoryEvent } from '../types';

const KIND: Record<EmployeeHistoryEvent['kind'], { label: string; tone: Tone }> = {
  join: { label: 'مباشرة', tone: 'emerald' },
  transfer: { label: 'نقل', tone: 'indigo' },
  exit: { label: 'ترك', tone: 'rose' },
  return: { label: 'رجوع', tone: 'teal' },
};

export function EmployeeHistoryCard({ employeeId }: { employeeId: string }) {
  const query = useQuery(`employee-history:${employeeId}`, () => fetchEmployeeHistory(employeeId));
  const events = query.data;
  // سيرفر قديم (null) أو ماكو أحداث: ما نعرض شي
  if (!events || events.length === 0) return null;
  return (
    <div className="mb-6" data-testid="employee-history">
      <h4 className="text-sm font-bold text-white flex items-center gap-2 mb-3">
        <History className="w-4 h-4 text-indigo-300" /> سجل الموظف
      </h4>
      <ol className="space-y-2">
        {events.map((ev, i) => (
          <li key={`${ev.date}-${ev.kind}-${i}`} className="flex items-start gap-2 text-xs">
            <span className="font-mono text-slate-400 shrink-0 w-24" dir="rtl">{arabicDate(ev.date, true)}</span>
            <Badge tone={KIND[ev.kind]?.tone ?? 'slate'}>{KIND[ev.kind]?.label ?? ev.kind}</Badge>
            <span className="text-slate-200">{ev.text}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}
