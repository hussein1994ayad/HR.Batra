'use client';

// غيابات اليوم مقسّمة حسب الفروع (+ "بدون فرع")، مع بحث بالاسم.

import { useMemo, useState } from 'react';
import { AlertTriangle, Building2, CheckCircle } from 'lucide-react';
import { Avatar, Badge, Card, CardHeader, EmptyState, SearchInput } from '@/components/ui';
import type { DashboardData } from '../api';

export function AbsentTodayCard({ data, tracked }: { data: DashboardData; tracked: number }) {
  const [absentSearch, setAbsentSearch] = useState('');

  const absentGroups = useMemo(() => {
    const q = absentSearch.trim().toLowerCase();
    const list = q ? data.absentList.filter((e) => (e.full_name || '').toLowerCase().includes(q)) : data.absentList;
    return [
      ...data.branches.map((b) => ({ id: b.id, name: b.name, members: list.filter((e) => e.branch_id === b.id) })),
      { id: '__none', name: 'بدون فرع', members: list.filter((e) => !e.branch_id) },
    ].filter((g) => g.members.length > 0);
  }, [data, absentSearch]);

  return (
    <Card id="absent-section" className="scroll-mt-24">
      <CardHeader
        icon={AlertTriangle}
        tone="rose"
        title={
          <>
            غيابات اليوم <Badge tone="rose">{data.stats.absentToday}</Badge>
          </>
        }
        description="موظفون لم يسجلوا دخولهم اليوم وغير مجازين، مقسمون حسب الفروع"
        actions={
          data.absentList.length > 0 && (
            <SearchInput value={absentSearch} onChange={setAbsentSearch} placeholder="ابحث عن موظف..." className="w-full sm:w-64" />
          )
        }
      />

      {data.absentList.length === 0 ? (
        tracked === 0
          ? <EmptyState icon={CheckCircle} tone="emerald" title="اليوم عطلة" description="ماكو أحد عنده دوام اليوم." />
          : <EmptyState icon={CheckCircle} tone="emerald" title="الجميع حاضرون!" description="لا توجد غيابات مسجلة لهذا اليوم." />
      ) : absentGroups.length === 0 ? (
        <p className="py-10 text-center text-xs text-slate-500">لا توجد نتائج مطابقة للبحث</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {absentGroups.map((group) => (
            <div key={group.id} className="rounded-2xl bg-slate-950/40 border border-slate-800/70 overflow-hidden flex flex-col">
              <div className="px-4 py-3 border-b border-slate-800/70 flex justify-between items-center">
                <span className="font-bold text-[13px] text-white flex items-center gap-2 min-w-0">
                  <Building2 className="w-4 h-4 text-indigo-400 shrink-0" />
                  <span className="truncate">{group.name}</span>
                </span>
                <Badge tone="rose">{group.members.length} غائب</Badge>
              </div>
              <ul className="p-2 space-y-0.5 overflow-y-auto max-h-[240px]">
                {group.members.map((emp) => (
                  <li key={emp.id} className="px-2.5 py-2 rounded-xl flex items-center gap-3 hover:bg-slate-800/40 transition-colors">
                    <Avatar name={emp.full_name} size="sm" />
                    <p className="text-xs font-semibold text-slate-200 truncate">{emp.full_name}</p>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
