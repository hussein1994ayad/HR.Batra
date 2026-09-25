'use client';

import { useState } from 'react';
import { Calendar as CalendarIcon, Loader2 } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { useTracking } from '@/features/tracking/useTracking';
import { AttendanceLogTable } from '@/features/tracking/components/AttendanceLogTable';
import { DecisionsTable } from '@/features/tracking/components/DecisionsTable';
import { EditAttendanceModal } from '@/features/tracking/components/EditAttendanceModal';
import { LiveTrailMap } from '@/features/tracking/components/LiveTrailMap';
import { ManualAttendanceModal } from '@/features/tracking/components/ManualAttendanceModal';
import { MonitoringStats } from '@/features/tracking/components/MonitoringStats';
import { TrackingFilters } from '@/features/tracking/components/TrackingFilters';
import { TrackingTabs } from '@/features/tracking/components/TrackingTabs';

export default function TrackingPage() {
  const t = useTracking();
  const [editingRecord, setEditingRecord] = useState<AttendanceRecord | null>(null);
  const [showManualModal, setShowManualModal] = useState(false);

  if (t.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12 flex-grow flex flex-col">
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex-grow flex flex-col justify-between">
        <TrackingFilters
          branches={t.branches}
          employees={t.employees}
          selectedBranch={t.selectedBranch}
          selectedEmployee={t.selectedEmployee}
          startDate={t.startDate}
          endDate={t.endDate}
          onBranchChange={t.changeBranch}
          onEmployeeChange={t.setSelectedEmployee}
          onStartDateChange={t.setStartDate}
          onEndDateChange={t.setEndDate}
          onRefresh={t.reload}
          onManualAttendance={() => setShowManualModal(true)}
        />

        <TrackingTabs activeTab={t.activeTab} pendingDecisions={t.pendingDecisions} onTabChange={t.setActiveTab} />

        {!t.startDate || !t.endDate ? (
          <div className="flex flex-col items-center justify-center p-12 bg-slate-900/20 border border-slate-800 rounded-3xl text-center">
            <CalendarIcon className="w-16 h-16 text-amber-500 mb-4 animate-bounce" />
            <h4 className="text-md font-bold text-white mb-2">
              {t.activeTab === 'monitoring'
                ? 'يرجى تحديد فترة زمنية (من - إلى) أولاً لعرض خريطة التتبع وسجل الحضور 📅'
                : 'يرجى تحديد فترة زمنية (من - إلى) أولاً لعرض قرارات الغياب والتأخير المعلقة 📅'}
            </h4>
            <p className="text-slate-400 text-xs">اختر التاريخ من شريط التحكم أعلاه للبدء</p>
          </div>
        ) : t.activeTab === 'monitoring' ? (
          <>
            <MonitoringStats
              attendanceCount={t.attendanceLogs.length}
              mockAttempts={t.securityLogs.length}
              activeZones={t.geofenceZones.length}
            />
            <AttendanceLogTable
              attendanceRows={t.attendanceRows}
              onExport={t.exportReport}
              onEdit={setEditingRecord}
              onForceCheckout={t.checkoutNow}
            />
            <LiveTrailMap
              attendanceLogs={t.attendanceLogs}
              selectedEmployeeForTrail={t.selectedEmployeeForTrail}
              liveTrackingActive={t.liveTrackingActive}
              trailCoordinates={t.trailCoordinates}
              markers={t.markers}
              polygons={t.polygons}
              center={t.mapView.center}
              zoom={t.mapView.zoom}
              onSelectEmployee={t.setSelectedEmployeeForTrail}
              onLiveTrackingChange={t.setLiveTrackingActive}
            />
          </>
        ) : (
          <DecisionsTable
            decisionsList={t.decisionsList}
            selectedAmounts={t.selectedAmounts}
            selectedReasons={t.selectedReasons}
            onAmountChange={(key, value) => t.setSelectedAmounts(prev => ({ ...prev, [key]: value }))}
            onReasonChange={(key, value) => t.setSelectedReasons(prev => ({ ...prev, [key]: value }))}
            onDecide={t.decide}
          />
        )}
      </div>

      {editingRecord && (
        <EditAttendanceModal
          record={editingRecord}
          saving={t.loading}
          onClose={() => setEditingRecord(null)}
          onSave={async (checkIn, checkOut) => {
            if (await t.updateTimes(editingRecord, checkIn, checkOut)) setEditingRecord(null);
          }}
        />
      )}

      {showManualModal && (
        <ManualAttendanceModal
          employees={t.employees}
          defaultDate={t.endDate}
          saving={t.loading}
          onClose={() => setShowManualModal(false)}
          onSave={async (entry) => {
            if (await t.addManualAttendance(entry)) setShowManualModal(false);
          }}
        />
      )}
    </div>
  );
}
