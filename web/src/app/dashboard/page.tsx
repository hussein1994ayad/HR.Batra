'use client';

import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { useDashboard } from '@/features/dashboard/useDashboard';
import { AbsenteesByBranch } from '@/features/dashboard/components/AbsenteesByBranch';
import { AnnouncementModal } from '@/features/dashboard/components/AnnouncementModal';
import { QuickActions } from '@/features/dashboard/components/QuickActions';
import { QuickAddEmployeeModal } from '@/features/dashboard/components/QuickAddEmployeeModal';
import { SecurityIncidents } from '@/features/dashboard/components/SecurityIncidents';
import { StatCards } from '@/features/dashboard/components/StatCards';

export default function DashboardPage() {
  const d = useDashboard();
  const [showAnnounceModal, setShowAnnounceModal] = useState(false);
  const [showAddEmployeeModal, setShowAddEmployeeModal] = useState(false);

  if (d.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-indigo-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <StatCards stats={d.stats} />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <SecurityIncidents securityLogs={d.securityLogs} incidentCount={d.stats.securityIncidents} />
        <QuickActions onAddEmployee={() => setShowAddEmployeeModal(true)} onAnnounce={() => setShowAnnounceModal(true)} />
      </div>

      <AbsenteesByBranch absentList={d.absentList} branches={d.branches} absentCount={d.stats.absentToday} />

      {showAnnounceModal && (
        <AnnouncementModal
          branches={d.branches}
          employeesList={d.employeesList}
          actionLoading={d.actionLoading}
          onClose={() => setShowAnnounceModal(false)}
          onSubmit={async (target, text) => {
            if (await d.postAnnouncement(target, text)) setShowAnnounceModal(false);
          }}
        />
      )}

      {showAddEmployeeModal && (
        <QuickAddEmployeeModal
          branches={d.branches}
          departments={d.departments}
          actionLoading={d.actionLoading}
          onClose={() => setShowAddEmployeeModal(false)}
          onSubmit={d.addEmployee}
        />
      )}
    </div>
  );
}
