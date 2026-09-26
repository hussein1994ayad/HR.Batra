import { Archive, Bell, Building, CheckCircle2 } from 'lucide-react';
import type { Branch } from '@/lib/db-types';
import { Badge, Button, FilterSelect, SearchInput, SegmentedTabs } from '@/components/ui';

export type PayrollStatusFilter = 'all' | 'pending' | 'issued';

type Props = {
  searchTerm: string;
  onSearchChange: (value: string) => void;
  selectedBranch: string;
  onBranchChange: (branchId: string) => void;
  branches: Pick<Branch, 'id' | 'name'>[];
  statusFilter: PayrollStatusFilter;
  onStatusFilterChange: (value: PayrollStatusFilter) => void;
  pendingCount: number;
  isMonthArchived: boolean;
  sendingNotifs: boolean;
  archiving: boolean;
  onOpenBulk: () => void;
  onSendBranchNotifications: () => void;
  onArchiveMonth: () => void;
};

/** البحث والفلاتر، واعتماد رواتب الفرع، وإشعار الفرع، وأرشفة الشهر. */
export function PayrollToolbar({
  searchTerm, onSearchChange, selectedBranch, onBranchChange, branches, statusFilter, onStatusFilterChange, pendingCount,
  isMonthArchived, sendingNotifs, archiving, onOpenBulk, onSendBranchNotifications, onArchiveMonth,
}: Props) {
  return (
    <div className="flex flex-col xl:flex-row xl:items-center justify-between gap-3 mb-5 print:hidden">
      <div className="flex flex-col sm:flex-row gap-2">
        <SearchInput value={searchTerm} onChange={onSearchChange} placeholder="ابحث باسم الموظف..." className="w-full sm:w-60" />
        <FilterSelect icon={Building} value={selectedBranch} onChange={onBranchChange} className="sm:w-44">
          <option value="all">جميع الفروع</option>
          {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
        </FilterSelect>
        <SegmentedTabs
          value={statusFilter}
          onChange={onStatusFilterChange}
          options={[
            { value: 'all', label: 'الكل' },
            { value: 'pending', label: 'غير معتمد' },
            { value: 'issued', label: 'معتمد' },
          ]}
        />
      </div>
      <div className="flex flex-wrap gap-2">
        {isMonthArchived ? (
          <Badge tone="violet" className="h-9 px-3"><Archive className="w-3.5 h-3.5" /> مؤرشف ومغلق مالياً</Badge>
        ) : (
          <>
            <Button variant="success" icon={CheckCircle2} disabled={pendingCount === 0} onClick={onOpenBulk}>
              اعتماد رواتب {selectedBranch === 'all' ? 'الكل' : 'الفرع'} ({pendingCount})
            </Button>
            {selectedBranch !== 'all' && (
              <Button variant="secondary" icon={Bell} loading={sendingNotifs} onClick={onSendBranchNotifications}>
                إشعار الفرع بالكشوف
              </Button>
            )}
            <Button variant="soft" icon={Archive} loading={archiving} onClick={onArchiveMonth}>
              أرشفة وإغلاق الشهر
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
