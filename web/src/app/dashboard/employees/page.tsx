'use client';

import { useMemo, useState } from 'react';
import { Loader2 } from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { useEmployees } from '@/features/employees/useEmployees';
import { filterEmployees } from '@/features/employees/logic';
import { AddEmployeeModal } from '@/features/employees/components/AddEmployeeModal';
import { ArchivedEmployeesTable } from '@/features/employees/components/ArchivedEmployeesTable';
import { DeleteEmployeeModal } from '@/features/employees/components/DeleteEmployeeModal';
import { DeviceRequestsAlert } from '@/features/employees/components/DeviceRequestsAlert';
import { DirectoryHeader } from '@/features/employees/components/DirectoryHeader';
import { DirectoryTabs } from '@/features/employees/components/DirectoryTabs';
import { DocumentPreviewModal } from '@/features/employees/components/DocumentPreviewModal';
import { EditEmployeeModal } from '@/features/employees/components/EditEmployeeModal';
import { EmployeeProfileModal } from '@/features/employees/components/EmployeeProfileModal';
import { EmployeesTable } from '@/features/employees/components/EmployeesTable';

export default function EmployeesPage() {
  const e = useEmployees();
  const [activeTab, setActiveTab] = useState<'active' | 'archived'>('active');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedBranch, setSelectedBranch] = useState('all');

  const [showAddModal, setShowAddModal] = useState(false);
  const [editing, setEditing] = useState<Employee | null>(null);
  const [deleting, setDeleting] = useState<Employee | null>(null);
  const [profile, setProfile] = useState<Employee | null>(null);
  const [preview, setPreview] = useState<{ url: string; title: string } | null>(null);

  const filteredEmployees = useMemo(() => filterEmployees({
    employees: e.employees, departments: e.departments, branches: e.branches, searchTerm, branchId: selectedBranch,
  }), [e.employees, e.departments, e.branches, searchTerm, selectedBranch]);

  if (e.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      {e.deviceRequests.length > 0 && (
        <DeviceRequestsAlert
          deviceRequests={e.deviceRequests}
          actionLoading={e.actionLoading}
          onProcess={(request, approve) => void e.processDeviceRequest(request, approve)}
        />
      )}

      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
        <DirectoryTabs activeTab={activeTab} archivedCount={e.archivedEmployees.length} onTabChange={setActiveTab} />

        {activeTab === 'active' ? (
          <>
            <DirectoryHeader
              branches={e.branches}
              searchTerm={searchTerm}
              selectedBranch={selectedBranch}
              onSearchChange={setSearchTerm}
              onBranchChange={setSelectedBranch}
              onAdd={() => setShowAddModal(true)}
            />
            <EmployeesTable
              employees={filteredEmployees}
              actionLoading={e.actionLoading}
              onOpenProfile={setProfile}
              onEdit={setEditing}
              onToggleLock={(emp) => void e.toggleDeviceLock(emp)}
              onResetDevice={(emp) => void e.resetDevice(emp)}
              onDelete={setDeleting}
            />
          </>
        ) : (
          <ArchivedEmployeesTable
            archivedEmployees={e.archivedEmployees}
            actionLoading={e.actionLoading}
            onRestore={(record) => void e.restoreArchived(record)}
            onDestroy={(record) => void e.destroyArchived(record)}
          />
        )}
      </div>

      {showAddModal && (
        <AddEmployeeModal
          branches={e.branches}
          saving={e.actionLoading === 'create_emp'}
          onClose={() => setShowAddModal(false)}
          onSubmit={async (values, documents) => {
            if (await e.addEmployee(values, documents)) setShowAddModal(false);
          }}
        />
      )}

      {editing && (
        <EditEmployeeModal
          selectedEmployee={editing}
          branches={e.branches}
          saving={e.actionLoading === 'update_emp'}
          onClose={() => setEditing(null)}
          onSubmit={async (values, keptDocuments, newDocuments) => {
            if (await e.editEmployee(editing, values, keptDocuments, newDocuments)) setEditing(null);
          }}
        />
      )}

      {deleting && (
        <DeleteEmployeeModal
          employeeToDelete={deleting}
          saving={e.actionLoading === 'delete_emp'}
          onClose={() => setDeleting(null)}
          onSubmit={async (deleteType, reason) => {
            if (await e.removeEmployee(deleting, deleteType, reason)) setDeleting(null);
          }}
        />
      )}

      {profile && (
        <EmployeeProfileModal
          profileEmployee={profile}
          onClose={() => setProfile(null)}
          onEdit={(emp) => {
            setProfile(null);
            setEditing(emp);
          }}
          onPreview={(url, title) => setPreview({ url, title })}
        />
      )}

      {preview && (
        <DocumentPreviewModal previewDocUrl={preview.url} previewDocTitle={preview.title} onClose={() => setPreview(null)} />
      )}
    </div>
  );
}
