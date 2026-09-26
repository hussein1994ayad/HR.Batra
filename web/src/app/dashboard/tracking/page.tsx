'use client';

import { useState } from 'react';
import { CalendarRange } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { EmptyState, PageSkeleton, cn } from '@/components/ui';
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

  if (t.loading) return <PageSkeleton />;

  const hasPeriod = !!t.startDate && !!t.endDate;
  const stale = t.refreshing && 'opacity-60';

  return (
    <div className="space-y-6 pb-12">
      <TrackingFilters
        branches={t.branches}
        employees={t.employees}
        selectedBranch={t.selectedBranch}
        selectedEmployee={t.selectedEmployee}
        startDate={t.startDate}
        endDate={t.endDate}
        refreshing={t.refreshing}
        onBranchChange={t.changeBranch}
        onEmployeeChange={t.setSelectedEmployee}
        onStartDateChange={t.setStartDate}
        onEndDateChange={t.setEndDate}
        onRefresh={t.reload}
        onManualAttendance={() => setShowManualModal(true)}
      />

      {!hasPeriod ? (
        <EmptyState
          icon={CalendarRange}
          tone="amber"
          title="حدد فترة زمنية (من - إلى) أولاً"
          description="اختر التاريخ من شريط التحكم أعلاه لعرض سجل الحضور والخريطة وقرارات الغياب والتأخير."
        />
      ) : (
        <>
          <div className={cn('transition-opacity', stale)}>
            <MonitoringStats
              attendanceCount={t.attendanceLogs.length}
              lateCount={t.attendanceLogs.filter(a => a.status === 'late').length}
              mockAttempts={t.securityLogs.length}
              activeZones={t.geofenceZones.length}
            />
          </div>

          <TrackingTabs activeTab={t.activeTab} pendingDecisions={t.pendingDecisions} onTabChange={t.setActiveTab} />

          {t.activeTab === 'monitoring' ? (
            <>
              <div className={cn('transition-opacity', stale)}>
                <AttendanceLogTable
                  attendanceRows={t.attendanceRows}
                  busyKey={t.busyKey}
                  onExport={t.exportReport}
                  onEdit={setEditingRecord}
                  onForceCheckout={t.checkoutNow}
                />
              </div>
              <LiveTrailMap
                attendanceLogs={t.attendanceLogs}
                selectedEmployeeForTrail={t.selectedEmployeeForTrail}
                liveTrackingActive={t.liveTrackingActive}
                trailCoordinates={t.trailCoordinates}
                detectedStops={t.detectedStops}
                markers={t.markers}
                polygons={t.polygons}
                center={t.mapView.center}
                zoom={t.mapView.zoom}
                onSelectEmployee={t.setSelectedEmployeeForTrail}
                onLiveTrackingChange={t.setLiveTrackingActive}
              />
            </>
          ) : (
            <div className={cn('transition-opacity', stale)}>
              <DecisionsTable
                decisionsList={t.decisionsList}
                selectedAmounts={t.selectedAmounts}
                selectedReasons={t.selectedReasons}
                busyKey={t.busyKey}
                onAmountChange={(key, value) => t.setSelectedAmounts(prev => ({ ...prev, [key]: value }))}
                onReasonChange={(key, value) => t.setSelectedReasons(prev => ({ ...prev, [key]: value }))}
                onDecide={t.decide}
              />
            </div>
          )}
        </>
      )}

      {editingRecord && (
        <EditAttendanceModal
          record={editingRecord}
          saving={t.busyKey === 'edit'}
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
          saving={t.busyKey === 'manual'}
          onClose={() => setShowManualModal(false)}
          onSave={async (entry) => {
            if (await t.addManualAttendance(entry)) setShowManualModal(false);
          }}
        />
      )}
    </div>
  );
}
