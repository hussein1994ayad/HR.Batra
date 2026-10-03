'use client';

import { useState } from 'react';
import { CalendarRange } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { EmptyState, PageSkeleton, cn } from '@/components/ui';
import { useTracking } from '@/features/tracking/useTracking';
import { useConfirm } from '@/components/confirm';
import { AttendanceLogTable } from '@/features/tracking/components/AttendanceLogTable';
import { DecisionsTable } from '@/features/tracking/components/DecisionsTable';
import { EditAttendanceModal } from '@/features/tracking/components/EditAttendanceModal';
import { LiveTrailMap } from '@/features/tracking/components/LiveTrailMap';
import { ManualAttendanceModal } from '@/features/tracking/components/ManualAttendanceModal';
import { resolveWorkSchedule } from '@/lib/schedules';
import { MonitoringStats } from '@/features/tracking/components/MonitoringStats';
import { TrackingFilters } from '@/features/tracking/components/TrackingFilters';
import { TrackingTabs } from '@/features/tracking/components/TrackingTabs';

export default function TrackingPage() {
  const t = useTracking();
  const confirm = useConfirm();
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
              activeZones={t.branches.filter(b => b.latitude != null && b.longitude != null && (b.radius_meters ?? 0) > 0).length}
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
                selectedReasons={t.selectedReasons}
                busyKey={t.busyKey}
                onReasonChange={(key, value) => t.setSelectedReasons(prev => ({ ...prev, [key]: value }))}
                onDecide={async (item, status, reason) => {
                  // قرار مالي: تأكيد قبل الخصم أو الإعفاء (مثل صفحة الرواتب)
                  const apply = status === 'applied';
                  const what = item.type === 'late' ? 'التأخير' : 'الغياب';
                  const ok = await confirm({
                    title: apply ? `تطبيق خصم ${what}؟` : `إعفاء من ${what}؟`,
                    message: `${item.employee.full_name} · ${item.date}\n${apply ? 'يُخصم من راتب المسير ويوصل للموظف إشعار.' : 'ما ينخصم شي ويوصل للموظف إشعار بالإعفاء.'}`,
                    confirmLabel: apply ? 'تطبيق الخصم' : 'إعفاء',
                    tone: apply ? 'warning' : 'primary',
                  });
                  if (ok) await t.decide(item, status, reason);
                }}
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
          shiftFor={(id) => {
            const emp = t.employees.find((e) => e.id === id);
            const ws = emp ? resolveWorkSchedule(emp, t.workSchedules) : undefined;
            return ws?.check_in_time && ws.check_out_time
              ? { start: ws.check_in_time.slice(0, 5), end: ws.check_out_time.slice(0, 5) }
              : undefined;
          }}
          onClose={() => setShowManualModal(false)}
          onSave={async (entry) => {
            if (await t.addManualAttendance(entry)) setShowManualModal(false);
          }}
        />
      )}
    </div>
  );
}
