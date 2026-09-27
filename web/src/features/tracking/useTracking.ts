'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { getLocalDateStr } from '@/lib/dates';
import { errorMessage } from '@/lib/error-utils';
import type { AttendanceRecord } from '@/lib/db-types';
import {
  fetchTrackingDataset, fetchTrailPoints, forceCheckout, saveDecision, saveManualAttendance,
  subscribeToEmployeeLocations, updateAttendanceTimes, type TrackingDataset,
} from './api';
import { exportDisciplineReport } from './exportReport';
import { analyzeTrail, buildAttendanceRows, buildDecisions, buildMapMarkers, decisionKey, parseZonePolygons } from './logic';
import type { Decision, DetectedStop } from './types';

const EMPTY: TrackingDataset = {
  geofenceZones: [], branches: [], employees: [], workSchedules: [], leaveRequests: [], attendanceLogs: [], securityLogs: [],
};
const BAGHDAD: [number, number] = [33.3152, 44.3661];

/** حالة صفحة المراقبة: البيانات، الفلاتر، مسار الحركة، القرارات، والإجراءات. */
export function useTracking() {
  // loading: أول تحميل فقط (هيكل الصفحة). refreshing: إعادة التحميل مع بقاء البيانات ظاهرة.
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [data, setData] = useState<TrackingDataset>(EMPTY);

  const [startDate, setStartDate] = useState(getLocalDateStr);
  const [endDate, setEndDate] = useState(getLocalDateStr);
  const [selectedBranch, setSelectedBranch] = useState('all');
  const [selectedEmployee, setSelectedEmployee] = useState('all');
  const [activeTab, setActiveTab] = useState<'monitoring' | 'decisions'>('monitoring');

  const [selectedReasons, setSelectedReasons] = useState<Record<string, string>>({});
  const [selectedAmounts, setSelectedAmounts] = useState<Record<string, string>>({});

  // مسار الحركة
  const [selectedEmployeeForTrail, setSelectedEmployeeForTrail] = useState<string | null>(null);
  const [liveTrackingActive, setLiveTrackingActive] = useState(false);
  const [trailCoordinates, setTrailCoordinates] = useState<[number, number][]>([]);
  const [detectedStops, setDetectedStops] = useState<DetectedStop[]>([]);
  const [mapView, setMapView] = useState<{ center: [number, number]; zoom: number }>({ center: BAGHDAD, zoom: 12 });

  const loadData = useCallback(async () => {
    setRefreshing(true);
    try {
      setData(await fetchTrackingDataset({ startDate, endDate, selectedBranch, selectedEmployee }));
    } catch (err: unknown) {
      console.error(err);
      toast.error(`تعذر تحميل بيانات المراقبة: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [startDate, endDate, selectedBranch, selectedEmployee]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب البيانات عند تغيّر الفلاتر
    void loadData();
  }, [loadData]);

  const loadTrail = useCallback(async (employeeId: string, dateStr: string) => {
    try {
      const { coords, stops } = analyzeTrail(await fetchTrailPoints(employeeId, dateStr));
      setTrailCoordinates(coords);
      setDetectedStops(stops);
      if (coords.length > 0) setMapView({ center: coords[coords.length - 1], zoom: 15 });
    } catch (err) {
      console.error('Failed to fetch trail data:', err);
    }
  }, []);

  useEffect(() => {
    if (!selectedEmployeeForTrail) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- مسح المسار عند إلغاء اختيار الموظف
      setTrailCoordinates([]);
      setDetectedStops([]);
      return;
    }
    void loadTrail(selectedEmployeeForTrail, endDate);
    if (!liveTrackingActive) return;

    return subscribeToEmployeeLocations(selectedEmployeeForTrail, (point) => {
      if (Number(point.latitude) && Number(point.longitude)) {
        toast.success('موقع جديد مستلم في الوقت المباشر! 📍');
        void loadTrail(selectedEmployeeForTrail, endDate);
      }
    });
  }, [selectedEmployeeForTrail, liveTrackingActive, endDate, loadTrail]);

  // ------------------------------------------------------------------
  // مشتقات
  // ------------------------------------------------------------------
  const decisionsList = useMemo(() => buildDecisions({
    startDate, endDate, selectedBranch, selectedEmployee,
    employees: data.employees, workSchedules: data.workSchedules,
    leaveRequests: data.leaveRequests, attendanceLogs: data.attendanceLogs,
  }), [data, startDate, endDate, selectedBranch, selectedEmployee]);

  const attendanceRows = useMemo(() => buildAttendanceRows(data.attendanceLogs, decisionsList), [data.attendanceLogs, decisionsList]);

  const markers = useMemo(() => buildMapMarkers({
    attendanceLogs: data.attendanceLogs, securityLogs: data.securityLogs,
    selectedEmployeeForTrail, trailCoordinates, detectedStops,
  }), [data, selectedEmployeeForTrail, trailCoordinates, detectedStops]);

  const polygons = useMemo(() => parseZonePolygons(data.geofenceZones), [data.geofenceZones]);
  const pendingDecisions = decisionsList.filter(d => d.deductionStatus === 'pending').length;
  const fallbackBranchId = data.branches[0]?.id ?? null;

  // ------------------------------------------------------------------
  // الإجراءات
  // ------------------------------------------------------------------
  const run = async (key: string, action: () => Promise<void>, success: string, failure: (err: unknown) => string) => {
    setBusyKey(key);
    try {
      await action();
      toast.success(success);
      await loadData();
      return true;
    } catch (err: unknown) {
      toast.error(failure(err));
      return false;
    } finally {
      setBusyKey(null);
    }
  };

  const changeBranch = (branchId: string) => {
    setSelectedBranch(branchId);
    setSelectedEmployee('all');
  };

  const updateTimes = (record: AttendanceRecord, checkIn: string, checkOut: string) =>
    run('edit', () => updateAttendanceTimes(record, checkIn, checkOut, endDate),
      'تم تحديث أوقات الدوام بنجاح! ✅', () => 'حدث خطأ أثناء التحديث.');

  const addManualAttendance = (entry: { employeeId: string; date: string; checkIn: string; checkOut: string }) => {
    const branchId = data.employees.find(e => e.id === entry.employeeId)?.branch_id || fallbackBranchId;
    if (!branchId) {
      toast.error('حدث خطأ: الموظف المختار غير مربوط بفرع، والفرع الافتراضي للمؤسسة غير متوفر.');
      return Promise.resolve(false);
    }
    return run('manual', () => saveManualAttendance({ ...entry, branchId }),
      'تم تسجيل الحضور اليدوي بنجاح! ✅', (err) => `حدث خطأ: ${errorMessage(err)}`);
  };

  const checkoutNow = (recordId: string) =>
    run(`checkout_${recordId}`, () => forceCheckout(recordId), 'تم تسجيل خروج الموظف بنجاح!', () => 'حدث خطأ أثناء تسجيل الخروج.');

  const decide = (item: Decision, status: 'applied' | 'ignored', reason: string, amount: number) =>
    run(decisionKey(item), () => saveDecision({
      employee: item.employee, type: item.type, date: item.date, status, recordId: item.id, reason, amount, fallbackBranchId,
    }), 'تم حفظ القرار وإرسال إشعار للموظف بنجاح! 🔔', (err) => `حدث خطأ أثناء حفظ القرار: ${errorMessage(err)}`);

  const exportReport = () => {
    try {
      exportDisciplineReport({
        rows: attendanceRows, decisionsList, selectedAmounts,
        leaveRequests: data.leaveRequests, securityLogs: data.securityLogs,
        branches: data.branches, employees: data.employees,
        startDate, endDate, selectedBranch, selectedEmployee,
      });
    } catch {
      toast.error('حدث خطأ أثناء تصدير التقرير');
    }
  };

  return {
    loading, refreshing, busyKey, ...data,
    startDate, setStartDate, endDate, setEndDate,
    selectedBranch, changeBranch, selectedEmployee, setSelectedEmployee,
    activeTab, setActiveTab,
    selectedAmounts, setSelectedAmounts, selectedReasons, setSelectedReasons,
    selectedEmployeeForTrail, setSelectedEmployeeForTrail, liveTrackingActive, setLiveTrackingActive,
    trailCoordinates, detectedStops, mapView, markers, polygons,
    decisionsList, pendingDecisions, attendanceRows,
    reload: loadData, updateTimes, addManualAttendance, checkoutNow, decide, exportReport,
  };
}
