import { Building2, Clock, RefreshCw, UserPlus, Users } from 'lucide-react';
import type { Branch } from '@/lib/db-types';
import { Button, FilterSelect, Input, PageHeader } from '@/components/ui';
import type { TrackedEmployee } from '../types';

type Props = {
  branches: Branch[];
  employees: TrackedEmployee[];
  selectedBranch: string;
  selectedEmployee: string;
  startDate: string;
  endDate: string;
  refreshing?: boolean;
  onBranchChange: (branchId: string) => void;
  onEmployeeChange: (employeeId: string) => void;
  onStartDateChange: (date: string) => void;
  onEndDateChange: (date: string) => void;
  onRefresh: () => void;
  onManualAttendance: () => void;
};

/** العنوان وفلاتر الفرع والفترة والموظف وزر الحضور اليدوي. */
export function TrackingFilters({
  branches, employees, selectedBranch, selectedEmployee, startDate, endDate, refreshing,
  onBranchChange, onEmployeeChange, onStartDateChange, onEndDateChange, onRefresh, onManualAttendance,
}: Props) {
  const branchEmployees = employees.filter(e => selectedBranch === 'all' || e.branch_id === selectedBranch);
  return (
    <PageHeader
      icon={Clock}
      tone="emerald"
      title="الحضور والتتبع"
      description="سجلات البصمة، مسار الحركة على الخريطة، وقرارات الغياب والتأخير لفترة محددة"
      actions={
        <>
          <FilterSelect icon={Building2} value={selectedBranch} onChange={onBranchChange} className="w-40">
            <option value="all">جميع الفروع</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </FilterSelect>
          <FilterSelect icon={Users} value={selectedEmployee} onChange={onEmployeeChange} className="w-44">
            <option value="all">جميع الموظفين</option>
            {branchEmployees.map(e => <option key={e.id} value={e.id}>{e.full_name}</option>)}
          </FilterSelect>
          <div className="flex items-center gap-1.5">
            <Input type="date" value={startDate} onChange={e => onStartDateChange(e.target.value)} className="h-9 w-36 text-xs" dir="ltr" aria-label="من تاريخ" />
            <span className="text-xs text-slate-500">إلى</span>
            <Input type="date" value={endDate} onChange={e => onEndDateChange(e.target.value)} className="h-9 w-36 text-xs" dir="ltr" aria-label="إلى تاريخ" />
          </div>
          <Button size="sm" variant="secondary" icon={RefreshCw} loading={refreshing} onClick={onRefresh}>
            تحديث
          </Button>
          <Button size="sm" icon={UserPlus} onClick={onManualAttendance}>
            حضور يدوي
          </Button>
        </>
      }
    />
  );
}
