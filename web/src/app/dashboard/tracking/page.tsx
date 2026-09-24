'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { resolveWorkSchedule } from '@/lib/schedules';
import { errorMessage } from '@/lib/error-utils';
import type {
  AttendanceRecord, Branch, Employee, EmployeeRef, LeaveRequest, LocationPoint, WorkSchedule,
} from '@/lib/db-types';
import MapComponent from '@/components/MapComponent';
import { 
  MapPin, 
  Users, 
  Loader2,
  RefreshCw,
  Clock,
  Edit,
  Save,
  LogOut,
  Calendar as CalendarIcon,
  Building2,
  Map,
  Download
} from 'lucide-react';
import * as XLSX from 'xlsx';
import toast from 'react-hot-toast';

const formatLateDurationArabic = (minutes: number) => {
  if (minutes <= 0) return '0 دقيقة';
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;

  let hrsStr = '';
  if (hrs > 0) {
    if (hrs === 1) hrsStr = 'ساعة';
    else if (hrs === 2) hrsStr = 'ساعتين';
    else if (hrs >= 3 && hrs <= 10) hrsStr = `${hrs} ساعات`;
    else hrsStr = `${hrs} ساعة`;
  }

  let minsStr = '';
  if (mins > 0) {
    if (mins === 1) minsStr = 'دقيقة واحدة';
    else if (mins === 2) minsStr = 'دقيقتين';
    else if (mins >= 3 && mins <= 10) minsStr = `${mins} دقائق`;
    else minsStr = `${mins} دقيقة`;
  }

  if (hrsStr && minsStr) {
    return `${hrsStr} و ${minsStr}`;
  } else if (hrsStr) {
    return hrsStr;
  } else {
    return minsStr;
  }
};

// الإحداثيات مخزنة بأكثر من شكل عبر إصدارات التطبيق: [lat, lng] أو {lat, lng} أو {latitude, longitude}
type RawPoint =
  | [number | string, number | string]
  | { lat?: number | string; lng?: number | string; latitude?: number | string; longitude?: number | string };

type RawZone = { id: string; name: string; coordinates?: unknown; polygon_coordinates?: unknown };

type MockGpsAttempt = {
  id: string;
  employee_id: string;
  latitude: number | null;
  longitude: number | null;
  app_used: string | null;
  timestamp: string;
  employees?: EmployeeRef | null;
};

type TrackedEmployee = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id' | 'role'> & {
  departments?: { name: string } | null;
};

type AttendanceRow = AttendanceRecord & { is_virtual: boolean };

type DetectedStop = { lat: number; lng: number; startTime: Date; endTime: Date; duration: number };

type MapMarker = { lat: number; lng: number; popupText: string; isViolation?: boolean; color?: string };

type Decision = {
  id: string | null;
  type: 'late' | 'absent' | 'virtual_absent';
  employee: TrackedEmployee;
  date: string;
  time: string;
  duration: string;
  typeName: string;
  deductionStatus: string;
  reason: string;
  suggestedAmount: number;
};

export default function TrackingPage() {
  const [loading, setLoading] = useState(true);
  const [attendanceLogs, setAttendanceLogs] = useState<AttendanceRecord[]>([]);
  const [securityLogs, setSecurityLogs] = useState<MockGpsAttempt[]>([]);
  const [geofenceZones, setGeofenceZones] = useState<RawZone[]>([]);
  const [selectedCenter, setSelectedCenter] = useState<[number, number]>([33.3152, 44.3661]); // Baghdad default
  const [selectedZoom, setSelectedZoom] = useState(12);

  const getLocalDateStr = () => {
    const d = new Date();
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().split('T')[0];
  };

  // New states for advanced attendance — date range
  const [startDate, setStartDate] = useState(getLocalDateStr());
  const [endDate, setEndDate] = useState(getLocalDateStr());
  const [editingRecord, setEditingRecord] = useState<AttendanceRecord | null>(null);
  const [editCheckIn, setEditCheckIn] = useState('');
  const [editCheckOut, setEditCheckOut] = useState('');
  
  const [branches, setBranches] = useState<Branch[]>([]);
  const [selectedBranch, setSelectedBranch] = useState('all');
  const [selectedEmployee, setSelectedEmployee] = useState('all');

  // Manual attendance states
  const [employees, setEmployees] = useState<TrackedEmployee[]>([]);
  const [showManualModal, setShowManualModal] = useState(false);
  const [manualEmpId, setManualEmpId] = useState('');
  const [manualDate, setManualDate] = useState(startDate);
  const [manualCheckIn, setManualCheckIn] = useState('09:00');
  const [manualCheckOut, setManualCheckOut] = useState('17:00');

  // Decisions states
  const [activeTab, setActiveTab] = useState<'monitoring' | 'decisions'>('monitoring');
  const [workSchedules, setWorkSchedules] = useState<WorkSchedule[]>([]);
  const [leaveRequests, setLeaveRequests] = useState<LeaveRequest[]>([]);
  const [selectedReasons, setSelectedReasons] = useState<Record<string, string>>({});
  const [selectedAmounts, setSelectedAmounts] = useState<Record<string, string>>({});
  
  // Live Trail States
  const [selectedEmployeeForTrail, setSelectedEmployeeForTrail] = useState<string | null>(null);
  const [trailCoordinates, setTrailCoordinates] = useState<[number, number][]>([]);
  const [detectedStops, setDetectedStops] = useState<DetectedStop[]>([]);
  const [liveTrackingActive, setLiveTrackingActive] = useState(false);


  const fetchTrackingData = async () => {
    setLoading(true);
    try {
      const [resZones, resBranches, resEmps, resScheds, resLeaves] = await Promise.all([
        supabase.from('geofence_zones').select('*').eq('is_active', true),
        supabase.from('branches').select('*'),
        supabase.from('employees').select('id, full_name, branch_id, department_id, role, departments:departments!employees_department_id_fkey(name)').eq('is_active', true).order('full_name'),
        supabase.from('work_schedules').select('*'),
        supabase.from('leave_requests').select('*').eq('status', 'approved')
      ]);

      if (resZones.data) setGeofenceZones(resZones.data);
      if (resBranches.data) setBranches(resBranches.data);
      // supabase-js بدون أنواع مولّدة يستنتج العلاقة departments كمصفوفة، وهي فعلياً كائن واحد
      if (resEmps.data) setEmployees(resEmps.data as unknown as TrackedEmployee[]);
      if (resScheds.data) setWorkSchedules(resScheds.data);
      if (resLeaves.data) setLeaveRequests(resLeaves.data);

      // الحضور ومحاولات التزييف ضمن الفترة المحددة
      if (startDate && endDate) {
        let attQuery = supabase.from('attendance').select('*, employees!employee_id(full_name, branch_id)').gte('work_date', startDate).lte('work_date', endDate);
        if (selectedEmployee !== 'all') {
          attQuery = attQuery.eq('employee_id', selectedEmployee);
        }
        const [resAtt, resMock] = await Promise.all([
          attQuery,
          supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false })
        ]);

        let filteredAtt: AttendanceRecord[] = resAtt.data || [];
        if (selectedBranch !== 'all') {
          filteredAtt = filteredAtt.filter((log) => log.employees?.branch_id === selectedBranch);
        }
        setAttendanceLogs(filteredAtt);
        if (resMock.data) setSecurityLogs(resMock.data);
      } else {
        setAttendanceLogs([]);
        setSecurityLogs([]);
      }
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTrackingData();
  }, [startDate, endDate, selectedBranch, selectedEmployee]);

  const fetchTrailData = async (employeeId: string, dateStr: string) => {
    try {
      const startOfDay = new Date(`${dateStr}T00:00:00`).toISOString();
      const endOfDay = new Date(`${dateStr}T23:59:59.999`).toISOString();

      const { data, error } = await supabase
        .from('location_tracking')
        .select('latitude, longitude, timestamp')
        .eq('employee_id', employeeId)
        .gte('timestamp', startOfDay)
        .lte('timestamp', endOfDay)
        .order('timestamp', { ascending: true });

      if (error) throw error;

      if (data) {
        const rawCoords: [number, number][] = data.map((item: Pick<LocationPoint, 'latitude' | 'longitude'>) => [Number(item.latitude), Number(item.longitude)]);
        
        // 1. Filter out contiguous duplicates (stationary points) to prevent redundant paths
        const filteredCoords: [number, number][] = [];
        rawCoords.forEach((coord) => {
          if (filteredCoords.length === 0) {
            filteredCoords.push(coord);
          } else {
            const last = filteredCoords[filteredCoords.length - 1];
            // Euclidean distance threshold roughly 10 meters (~0.0001 degrees)
            const dist = Math.sqrt(Math.pow(last[0] - coord[0], 2) + Math.pow(last[1] - coord[1], 2));
            if (dist > 0.0001) {
              filteredCoords.push(coord);
            }
          }
        });
        
        setTrailCoordinates(filteredCoords);

        // 2. Detect stops (stationary for >= 5 minutes)
        const stops: DetectedStop[] = [];
        let stopStart: number | null = null;
        let stopCoords: [number, number] | null = null;

        for (let i = 0; i < data.length; i++) {
          const pt = data[i];
          const ptTime = new Date(pt.timestamp).getTime();

          if (i === 0) {
            stopStart = ptTime;
            stopCoords = [Number(pt.latitude), Number(pt.longitude)];
            continue;
          }

          const prevPt = data[i - 1];
          const prevTime = new Date(prevPt.timestamp).getTime();
          const dist = Math.sqrt(
            Math.pow(Number(pt.latitude) - Number(prevPt.latitude), 2) +
            Math.pow(Number(pt.longitude) - Number(prevPt.longitude), 2)
          );

          // If moved less than ~50 meters (~0.0005 degrees)
          if (dist < 0.0005) {
            // Still in the same stop
          } else {
            // Moved away! Calculate stop duration
            if (stopStart && stopCoords) {
              const durationMins = (prevTime - stopStart) / (1000 * 60);
              if (durationMins >= 5) {
                stops.push({
                  lat: stopCoords[0],
                  lng: stopCoords[1],
                  startTime: new Date(stopStart),
                  endTime: new Date(prevTime),
                  duration: Math.round(durationMins)
                });
              }
            }
            // Reset stop
            stopStart = ptTime;
            stopCoords = [Number(pt.latitude), Number(pt.longitude)];
          }
        }

        // Check final point stop
        if (stopStart && stopCoords && data.length > 0) {
          const lastTime = new Date(data[data.length - 1].timestamp).getTime();
          const durationMins = (lastTime - stopStart) / (1000 * 60);
          if (durationMins >= 5) {
            stops.push({
              lat: stopCoords[0],
              lng: stopCoords[1],
              startTime: new Date(stopStart),
              endTime: new Date(lastTime),
              duration: Math.round(durationMins)
            });
          }
        }

        setDetectedStops(stops);

        if (filteredCoords.length > 0) {
          setSelectedCenter(filteredCoords[filteredCoords.length - 1]);
          setSelectedZoom(15);
        }
      }
    } catch (err) {
      console.error('Failed to fetch trail data:', err);
    }
  };

  useEffect(() => {
    if (!selectedEmployeeForTrail) {
      setTrailCoordinates([]);
      setDetectedStops([]);
      return;
    }

    fetchTrailData(selectedEmployeeForTrail, endDate);

    if (!liveTrackingActive) return;

    const channel = supabase
      .channel(`location_tracking:live:${selectedEmployeeForTrail}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'location_tracking',
          filter: `employee_id=eq.${selectedEmployeeForTrail}`,
        },
        (payload: { new: LocationPoint }) => {
          const newLat = Number(payload.new.latitude);
          const newLng = Number(payload.new.longitude);
          if (newLat && newLng) {
            toast.success('موقع جديد مستلم في الوقت المباشر! 📍');
            fetchTrailData(selectedEmployeeForTrail, endDate);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [selectedEmployeeForTrail, liveTrackingActive, endDate]);

  const handleUpdateTimes = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingRecord) return;
    
    try {
      setLoading(true);
      const workDate = editingRecord.work_date || endDate;
      const checkInISO = editCheckIn ? new Date(`${workDate}T${editCheckIn}:00`).toISOString() : null;
      const checkOutISO = editCheckOut ? new Date(`${workDate}T${editCheckOut}:00`).toISOString() : null;
      
      const { error } = await supabase
        .from('attendance')
        .update({
          check_in_time: checkInISO,
          check_out_time: checkOutISO,
          status: checkOutISO ? 'present' : editingRecord.status
        })
        .eq('id', editingRecord.id);
        
      if (error) throw error;
      
      toast.success('تم تحديث أوقات الدوام بنجاح! ✅');
      setEditingRecord(null);
      fetchTrackingData();
    } catch {
      toast.error('حدث خطأ أثناء التحديث.');
    } finally {
      setLoading(false);
    }
  };

  const handleManualAttendanceSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!manualEmpId) {
      toast('الرجاء اختيار الموظف أولاً');
      return;
    }
    
    try {
      setLoading(true);
      const selectedEmpObj = employees.find(e => e.id === manualEmpId);
      const defaultBranchId = selectedEmpObj?.branch_id || (branches.length > 0 ? branches[0].id : null);
      
      if (!defaultBranchId) {
        throw new Error('الموظف المختار غير مربوط بفرع، والفرع الافتراضي للمؤسسة غير متوفر.');
      }
      
      const checkInISO = manualCheckIn ? new Date(`${manualDate}T${manualCheckIn}:00`).toISOString() : null;
      const checkOutISO = manualCheckOut ? new Date(`${manualDate}T${manualCheckOut}:00`).toISOString() : null;
      
      // Check if attendance already exists for this date and employee
      const { data: existing } = await supabase
        .from('attendance')
        .select('id')
        .eq('employee_id', manualEmpId)
        .eq('work_date', manualDate)
        .maybeSingle();
        
      if (existing) {
        const { error } = await supabase
          .from('attendance')
          .update({
            check_in_time: checkInISO,
            check_out_time: checkOutISO,
            status: 'present',
            branch_id: defaultBranchId
          })
          .eq('id', existing.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('attendance')
          .insert({
            employee_id: manualEmpId,
            work_date: manualDate,
            check_in_time: checkInISO,
            check_out_time: checkOutISO,
            status: 'present',
            branch_id: defaultBranchId
          });
        if (error) throw error;
      }
      
      toast.success('تم تسجيل الحضور اليدوي بنجاح! ✅');
      setShowManualModal(false);
      fetchTrackingData();
    } catch (err: unknown) {
      toast.error(`حدث خطأ: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  };

  const handleForceCheckout = async (recordId: string) => {
    try {
      setLoading(true);
      const now = new Date();
      const { error } = await supabase
        .from('attendance')
        .update({
          check_out_time: now.toISOString(),
          status: 'completed'
        })
        .eq('id', recordId);
        
      if (error) throw error;
      toast.success('تم تسجيل خروج الموظف بنجاح!');
      fetchTrackingData();
    } catch {
      toast.error('حدث خطأ أثناء تسجيل الخروج.');
    } finally {
      setLoading(false);
    }
  };

  const handleDecision = async (
    emp: TrackedEmployee,
    type: string,
    infractionDate: string,
    status: 'applied' | 'ignored',
    recordId: string | null,
    reason: string,
    amount: number
  ) => {
    try {
      setLoading(true);
      if (status === 'applied' && amount > 0) {
        await supabase.from('bonuses_deductions').insert({
          employee_id: emp.id,
          type: 'deduction',
          amount: amount,
          reason: reason,
          issue_date: infractionDate
        });
      }

      if (type === 'virtual_absent') {
        const defaultBranchId = emp.branch_id || (branches.length > 0 ? branches[0].id : null);
        if (!defaultBranchId) {
          toast.error('الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.');
          return;
        }

        // Check if attendance record already exists for this date and employee
        const { data: existing } = await supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', emp.id)
          .eq('work_date', infractionDate)
          .maybeSingle();

        if (existing) {
          const { error } = await supabase
            .from('attendance')
            .update({
              status: 'absent',
              deduction_status: status,
              deduction_reason: reason,
              branch_id: defaultBranchId
            })
            .eq('id', existing.id);
          if (error) throw error;
        } else {
          const { error } = await supabase.from('attendance').insert({
            employee_id: emp.id,
            work_date: infractionDate,
            status: 'absent',
            deduction_status: status,
            deduction_reason: reason,
            branch_id: defaultBranchId
          });
          if (error) throw error;
        }
      } else {
        const { error } = await supabase
          .from('attendance')
          .update({
            deduction_status: status,
            deduction_reason: reason
          })
          .eq('id', recordId);
        if (error) throw error;
      }

      // Add a notification for the employee based on rules:
      // - Deductions (status === 'applied') for lateness: ❌ Do NOT notify
      // - Absences (type === 'virtual_absent'): ✅ Notify employee of absence registration
      // - Waived/Ignored infractions (status === 'ignored'): ✅ Notify employee of waiver
      if (type === 'virtual_absent') {
        await supabase.from('notifications').insert({
          employee_id: emp.id,
          title: 'تسجيل غياب يومي ⚠️',
          body: `تم تسجيل غيابك عن العمل ليوم ${infractionDate} من قبل الإدارة. السبب: ${reason || 'غير محدد'}`,
          type: 'attendance'
        });
      } else if (status === 'ignored') {
        await supabase.from('notifications').insert({
          employee_id: emp.id,
          title: 'إعفاء من الخصم المالي ✅',
          body: `تم إعفاؤك من الخصم المالي المترتب على ${type === 'late' ? 'التأخير الصباحي' : 'الغياب'} ليوم ${infractionDate}.`,
          type: 'attendance'
        });
      }

      toast.success('تم حفظ القرار وإرسال إشعار للموظف بنجاح! 🔔');
      fetchTrackingData();
    } catch (err: unknown) {
      toast.error(`حدث خطأ أثناء حفظ القرار: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  };

  const formatHours = (checkIn?: string | null, checkOut?: string | null) => {
    if (!checkIn || !checkOut) return '-';
    const diffMs = new Date(checkOut).getTime() - new Date(checkIn).getTime();
    if (diffMs <= 0) return '-';
    const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
    const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
    return `${diffHrs} س و ${diffMins} د`;
  };

  const formatTimeInputValue = (dateString?: string | null) => {
    if (!dateString) return '';
    const d = new Date(dateString);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  };

  // سجلات الحضور + صفوف غياب افتراضية للموظفين الذين لم يبصموا في يوم عمل
  const buildAttendanceRows = (): AttendanceRow[] => [
    ...attendanceLogs.map(log => ({ ...log, is_virtual: false })),
    ...decisionsList.filter(d => d.type === 'virtual_absent').map(d => ({
      id: `virtual_${d.employee.id}_${d.date}`,
      is_virtual: true,
      employee_id: d.employee.id,
      branch_id: d.employee.branch_id ?? '',
      status: 'absent',
      work_date: d.date,
      check_in_time: null,
      check_out_time: null,
      employees: d.employee,
    })),
  ];

  const handleExportExcel = () => {
    try {
      const fullList = buildAttendanceRows();
      
      const excelData = fullList.map((log, index) => {
        const emp = log.employees;
        const branchName = branches.find(b => b.id === emp?.branch_id)?.name || 'غير محدد';
        
        // Day of the week in Arabic
        const arabicDays = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
        let dayName = '-';
        if (log.work_date) {
          const [y, m, d] = log.work_date.split('-').map(Number);
          const dayObj = new Date(y, m - 1, d);
          dayName = arabicDays[dayObj.getDay()];
        }

        // Find decision info
        const dec = decisionsList.find(d => d.employee.id === log.employee_id && d.date === log.work_date);
        
        let delayStr = '-';
        if (dec && dec.type === 'late') {
          delayStr = dec.duration || '-';
        }

        let decStatusStr = 'لا يوجد خصم';
        let decAmountStr = '-';
        if (dec) {
          // نفس مفتاح المبلغ المستعمل في جدول القرارات
          const rowKey = `${dec.employee.id}_${dec.type}_${dec.date}`;
          if (dec.deductionStatus === 'applied') {
            decStatusStr = 'تم اعتماد الخصم ✅';
            const amt = selectedAmounts[rowKey] || dec.suggestedAmount || 0;
            decAmountStr = `${Number(amt).toLocaleString('ar-IQ')} د.ع`;
          } else if (dec.deductionStatus === 'ignored') {
            decStatusStr = 'معفى من الخصم 🔓';
            decAmountStr = '0 د.ع (إعفاء)';
          } else {
            decStatusStr = 'بانتظار القرار ⏳';
            const amt = selectedAmounts[rowKey] || dec.suggestedAmount || 0;
            decAmountStr = `${Number(amt).toLocaleString('ar-IQ')} د.ع (مقترح)`;
          }
        }

        // Find approved leave
        const leave = leaveRequests.find(l => {
          if (l.employee_id !== log.employee_id) return false;
          const dTime = new Date(log.work_date).getTime();
          const sTime = new Date(l.start_date.split('T')[0]).getTime();
          const eTime = new Date(l.end_date.split('T')[0]).getTime();
          return dTime >= sTime && dTime <= eTime;
        });

        // Find GPS spoofing attempts on this date
        const spoofing = securityLogs.filter(s => {
          if (s.employee_id !== log.employee_id) return false;
          const sDate = new Date(s.timestamp).toISOString().split('T')[0];
          return sDate === log.work_date;
        });

        // Formulate detailed notes
        const notes = [];
        if (spoofing.length > 0) {
          notes.push(`🚨 تنبيه: كشف موقع وهمي (${spoofing.length} محاولة)`);
        }
        if (leave) {
          notes.push(`إجازة معتمدة (${leave.leave_type || 'اعتيادية'})`);
        }
        if (dec && dec.reason) {
          notes.push(`ملاحظة الانضباط: ${dec.reason}`);
        }
        const notesStr = notes.length > 0 ? notes.join(' | ') : 'سجل سليم وطبيعي';

        // Status mapping
        let attendanceStatus = 'حضور منتظم';
        if (log.is_virtual) {
          attendanceStatus = 'غياب بدون عذر ❌';
        } else if (log.status === 'late') {
          attendanceStatus = 'حضور متأخر ⚠️';
        } else if (log.status === 'absent') {
          attendanceStatus = 'غياب مسجل ❌';
        }

        return {
          'ت': index + 1,
          'اسم الموظف': emp?.full_name || 'غير محدد',
          'الفرع': branchName,
          'تاريخ الدوام': log.work_date,
          'اليوم': dayName,
          'وقت الدخول الفعلي': log.check_in_time ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
          'وقت الخروج الفعلي': log.check_out_time ? new Date(log.check_out_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
          'ساعات العمل': formatHours(log.check_in_time, log.check_out_time),
          'حالة الدوام': attendanceStatus,
          'مدة التأخير': delayStr,
          'حالة الخصم': decStatusStr,
          'قيمة الخصم (د.ع)': decAmountStr,
          'ملاحظات الانضباط والتنبيهات الذكية': notesStr
        };
      });

      // 1. Create a blank sheet with a professional title block
      const worksheet = XLSX.utils.aoa_to_sheet([
        ["كشف المراقبة والانضباط الوظيفي التفصيلي الموحد - شركة بترى"],
        [`الفترة المشمولة بالتقرير: من ${startDate} إلى ${endDate}`],
        [`فرع المؤسسة المصفى: ${selectedBranch === 'all' ? 'جميع الفروع' : (branches.find(b => b.id === selectedBranch)?.name || '')} | الموظف المصفى: ${selectedEmployee === 'all' ? 'جميع الموظفين' : (employees.find(e => e.id === selectedEmployee)?.full_name || '')}`],
        [`تاريخ ووقت استخراج التقرير: ${new Date().toLocaleString('ar-IQ', { hour12: true })}`],
        [] // Blank spacer row
      ]);

      // 2. Append the main json data starting at A6
      XLSX.utils.sheet_add_json(worksheet, excelData, { origin: "A6" });

      // 3. Set layout direction to RTL for Arabic reader
      worksheet['!dir'] = 'rtl';
      worksheet['!views'] = [{ RTL: true }];

      // 4. Merge headers for the title blocks (A1:M1, A2:M2, A3:M3, A4:M4)
      worksheet['!merges'] = [
        { s: { r: 0, c: 0 }, e: { r: 0, c: 12 } }, // Row 1
        { s: { r: 1, c: 0 }, e: { r: 1, c: 12 } }, // Row 2
        { s: { r: 2, c: 0 }, e: { r: 2, c: 12 } }, // Row 3
        { s: { r: 3, c: 0 }, e: { r: 3, c: 12 } }  // Row 4
      ];

      // 5. Adjust column widths dynamically to prevent clipping
      worksheet['!cols'] = [
        { wch: 6 },   // ت
        { wch: 28 },  // اسم الموظف
        { wch: 20 },  // الفرع
        { wch: 15 },  // تاريخ الدوام
        { wch: 12 },  // اليوم
        { wch: 16 },  // وقت الدخول الفعلي
        { wch: 16 },  // وقت الخروج الفعلي
        { wch: 16 },  // ساعات العمل
        { wch: 20 },  // حالة الدوام
        { wch: 15 },  // مدة التأخير
        { wch: 20 },  // حالة الخصم
        { wch: 22 },  // قيمة الخصم (د.ع)
        { wch: 45 }   // ملاحظات الانضباط والتنبيهات الذكية
      ];

      const workbook = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(workbook, worksheet, "كشف الانضباط والتتبع");
      XLSX.writeFile(workbook, `تقرير_الانضباط_والتتبع_شركة_بترى_${startDate}_الى_${endDate}.xlsx`);
    } catch {
      toast.error("حدث خطأ أثناء تصدير التقرير");
    }
  };

  const getMapMarkers = () => {
    const markers: MapMarker[] = [];
    attendanceLogs.forEach((log) => {
      if (log.check_in_lat && log.check_in_lng) {
        markers.push({
          lat: Number(log.check_in_lat),
          lng: Number(log.check_in_lng),
          isViolation: false,
          popupText: `
            <strong style="color: #0D9488; font-size: 13px;">حضور موظف فعال ✅</strong><br/>
            <strong>الاسم:</strong> ${log.employees?.full_name || 'موظف'}<br/>
            <strong>الوقت:</strong> ${new Date(log.check_in_time!).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}<br/>
            <strong>الحالة:</strong> ${log.status === 'late' ? 'متأخر ⚠️' : 'في الوقت المعتمد'}<br/>
            <strong>الجهاز:</strong> هاتف مسجل معتمد
          `
        });
      }
    });

    securityLogs.forEach((log) => {
      if (log.latitude && log.longitude) {
        markers.push({
          lat: Number(log.latitude),
          lng: Number(log.longitude),
          isViolation: true,
          popupText: `
            <strong style="color: #EF4444; font-size: 13px;">تنبيه خرق أمني: GPS وهمي 🚨</strong><br/>
            <strong>الموظف:</strong> ${log.employees?.full_name || 'غير معروف'}<br/>
            <strong>الوقت:</strong> ${new Date(log.timestamp).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}<br/>
            <strong>التطبيق المكتشف:</strong> ${log.app_used || 'وهمي غير مصنف'}<br/>
            <span style="color: #EF4444; font-weight: bold;">تم قفل ومنع تسجيل الدوام تلقائياً!</span>
          `
        });
      }
    });

    // Add latest trail marker for selected employee
    if (selectedEmployeeForTrail && trailCoordinates.length > 0) {
      const latest = trailCoordinates[trailCoordinates.length - 1];
      const empName = attendanceLogs.find(log => log.employee_id === selectedEmployeeForTrail)?.employees?.full_name || 'الموظف المختار';
      markers.push({
        lat: latest[0],
        lng: latest[1],
        color: '#3B82F6', // Glowing blue for live current location
        popupText: `
          <strong style="color: #3B82F6; font-size: 13px;">الموقع المباشر الحالي للموظف 📍</strong><br/>
          <strong>الموظف:</strong> ${empName}<br/>
          <strong>الحالة:</strong> متصل (أونلاين)<br/>
          <span style="color: #3B82F6; font-weight: bold;">يتم رصد الحركة الجغرافية تلقائياً...</span>
        `
      });
    }

    // Add detected stops markers
    detectedStops.forEach((stop, index) => {
      markers.push({
        lat: stop.lat,
        lng: stop.lng,
        color: '#EAB308', // Glowing yellow for stops
        popupText: `
          <strong style="color: #EAB308; font-size: 13px;">موقع توقف مؤقت ⏳ (وقفة رقم ${index + 1})</strong><br/>
          <strong>وقت البدء:</strong> ${stop.startTime.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}<br/>
          <strong>وقت النهاية:</strong> ${stop.endTime.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}<br/>
          <strong>المدة:</strong> ${formatLateDurationArabic(stop.duration)}<br/>
          <span style="color: #EAB308; font-weight: bold;">توقف الموظف في هذا الموقع لأكثر من 5 دقائق</span>
        `
      });
    });

    return markers;
  };

  const getMapPolygons = () => {
    return geofenceZones.map((zone) => {
      let coords: [number, number][] = [];
      const rawCoords = zone.coordinates || zone.polygon_coordinates;
      if (rawCoords) {
        try {
          const parsed = typeof rawCoords === 'string' ? JSON.parse(rawCoords) : rawCoords;
          if (Array.isArray(parsed)) {
            coords = parsed
              .map((pt: RawPoint): [number, number] => {
                if (Array.isArray(pt)) return [Number(pt[0]), Number(pt[1])];
                return [Number(pt.lat ?? pt.latitude), Number(pt.lng ?? pt.longitude)];
              })
              .filter((pt) => !isNaN(pt[0]) && !isNaN(pt[1]));
          }
        } catch (e) {
          console.error('Error parsing geofence zone coords:', e);
        }
      }

      return {
        name: zone.name,
        coords: coords
      };
    });
  };

  // Compile infractions (absences and latenesses) for decisions across date range
  const getDecisionsList = () => {
    if (!startDate || !endDate) return [];
    const list: Decision[] = [];

    // Generate array of all dates in range
    const allDates: string[] = [];
    const current = new Date(startDate);
    const end = new Date(endDate);
    while (current <= end) {
      allDates.push(current.toISOString().split('T')[0]);
      current.setDate(current.getDate() + 1);
    }

    const isDateWithinRange = (dStr: string, startStr: string, endStr: string) => {
      if (!dStr || !startStr || !endStr) return false;
      const d = new Date(dStr).getTime();
      const s = new Date(startStr.split('T')[0]).getTime();
      const e = new Date(endStr.split('T')[0]).getTime();
      return d >= s && d <= e;
    };

    allDates.forEach(dateStr => {
      employees.forEach(emp => {
        if (selectedBranch !== 'all' && emp.branch_id !== selectedBranch) return;
        if (selectedEmployee !== 'all' && emp.id !== selectedEmployee) return;

        const empSched = resolveWorkSchedule(emp, workSchedules);
        const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];
        
        const [year, month, day] = dateStr.split('-');
        const dayObj = new Date(Number(year), Number(month) - 1, Number(day));
        const weekday = dayObj.getDay();
        const isWorkingDay = workDays.includes(weekday);

        if (!isWorkingDay) return;

        const leaveRecord = leaveRequests.find(l => l.employee_id === emp.id && isDateWithinRange(dateStr, l.start_date, l.end_date));

        const attRecord = attendanceLogs.find(log => log.employee_id === emp.id && log.work_date === dateStr);

        if (attRecord) {
          if (attRecord.status === 'late') {
            const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
            const checkIn = new Date(attRecord.check_in_time ?? `${dateStr}T00:00:00`);
            const [h, m, s] = schedCheckIn.split(':').map(Number);
            const sched = new Date(checkIn);
            sched.setHours(h, m, s || 0, 0);
            const diffMs = checkIn.getTime() - sched.getTime();
            const lateMinutes = diffMs > 0 ? Math.floor(diffMs / (1000 * 60)) : 0;

            list.push({
              id: attRecord.id,
              type: 'late',
              employee: emp,
              date: dateStr,
              time: attRecord.check_in_time ? new Date(attRecord.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
              duration: formatLateDurationArabic(lateMinutes),
              typeName: 'التأخير الصباحي',
              deductionStatus: attRecord.deduction_status || 'pending',
              reason: attRecord.deduction_reason || `التأخير: ${formatLateDurationArabic(lateMinutes)}`,
              suggestedAmount: lateMinutes * 50
            });
          } else if (attRecord.status === 'absent') {
            list.push({
              id: attRecord.id,
              type: 'absent',
              employee: emp,
              date: dateStr,
              time: '-',
              duration: 'يوم واحد',
              typeName: 'الغياب',
              deductionStatus: attRecord.deduction_status || 'pending',
              reason: attRecord.deduction_reason || 'الغياب بدون إجازة',
              suggestedAmount: 25000
            });
          }
        } else {
          if (!leaveRecord) {
            list.push({
              id: null,
              type: 'virtual_absent',
              employee: emp,
              date: dateStr,
              time: '-',
              duration: 'يوم واحد',
              typeName: 'الغياب',
              deductionStatus: 'pending',
              reason: 'الغياب بدون إجازة',
              suggestedAmount: 25000
            });
          }
        }
      });
    });
    return list;
  };

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  const markers = getMapMarkers();
  const polygons = getMapPolygons();
  const decisionsList = getDecisionsList();
  const attendanceRows = buildAttendanceRows();

  return (
    <div className="space-y-8 pb-12 flex-grow flex flex-col">
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex-grow flex flex-col justify-between">
        
        {/* Header controller */}
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
          <div>
            <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
              <MapPin className="w-5 h-5 text-teal-400" />
              <span>مراقبة وإدارة الانضباط الوظيفي اليومي</span>
            </h3>
            <p className="text-[11px] text-slate-400">مراقبة وتسجيل حضور وانصراف الموظفين جغرافياً مع اتخاذ قرارات خصم الغيابات والتأخير يدوياً</p>
          </div>

          <div className="flex flex-col sm:flex-row items-center gap-3">
            <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
              <Building2 className="w-4 h-4 text-teal-400" />
              <select 
                value={selectedBranch}
                onChange={(e) => {
                  setSelectedBranch(e.target.value);
                  setSelectedEmployee('all');
                }}
                className="bg-transparent border-none text-white text-xs outline-none cursor-pointer min-w-[120px]"
              >
                <option value="all" className="bg-slate-900">جميع الفروع</option>
                {branches.map(b => (
                  <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
              <CalendarIcon className="w-4 h-4 text-teal-400" />
              <span className="text-[10px] text-slate-400 font-bold">من</span>
              <input 
                type="date" 
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
              />
            </div>

            <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
              <CalendarIcon className="w-4 h-4 text-amber-400" />
              <span className="text-[10px] text-slate-400 font-bold">إلى</span>
              <input 
                type="date" 
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
              />
            </div>

            <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
              <Users className="w-4 h-4 text-violet-400" />
              <select
                value={selectedEmployee}
                onChange={(e) => setSelectedEmployee(e.target.value)}
                className="bg-transparent border-none text-white text-xs outline-none appearance-none cursor-pointer min-w-[80px]"
              >
                <option value="all" className="bg-slate-900">جميع الموظفين</option>
                {employees.filter(emp => selectedBranch === 'all' || emp.branch_id === selectedBranch).map(emp => (
                  <option key={emp.id} value={emp.id} className="bg-slate-900">{emp.full_name}</option>
                ))}
              </select>
            </div>
            
            <button
              onClick={() => fetchTrackingData()}
              className="flex items-center gap-2 py-2 px-4 bg-slate-800 hover:bg-slate-750 text-white rounded-xl text-xs font-bold transition-all border border-slate-700/60 cursor-pointer"
            >
              <RefreshCw className="w-4 h-4" />
              <span className="hidden sm:inline">تحديث</span>
            </button>

            <button
              onClick={() => {
                setManualDate(endDate);
                setManualCheckIn('09:00');
                setManualCheckOut('17:00');
                setManualEmpId('');
                setShowManualModal(true);
              }}
              className="flex items-center gap-2 py-2 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
            >
              <Users className="w-4 h-4" />
              <span>تسجيل حضور يدوي</span>
            </button>
          </div>
        </div>

        {/* Custom Tabs */}
        <div className="flex border-b border-slate-800/80 mb-6 gap-6">
          <button
            onClick={() => setActiveTab('monitoring')}
            className={`pb-4 text-xs sm:text-sm font-bold transition-all relative cursor-pointer ${
              activeTab === 'monitoring' 
                ? 'text-teal-400 border-b-2 border-teal-400' 
                : 'text-slate-400 hover:text-white'
            }`}
          >
            المراقبة والخرائط المباشرة
          </button>
          <button
            onClick={() => setActiveTab('decisions')}
            className={`pb-4 text-xs sm:text-sm font-bold transition-all relative cursor-pointer flex items-center gap-2 ${
              activeTab === 'decisions' 
                ? 'text-teal-400 border-b-2 border-teal-400' 
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <span>قرارات الغياب والتأخير</span>
            {decisionsList.filter(d => d.deductionStatus === 'pending').length > 0 && (
              <span className="bg-amber-500 text-slate-950 font-extrabold text-[9px] px-1.5 py-0.5 rounded-full">
                {decisionsList.filter(d => d.deductionStatus === 'pending').length}
              </span>
            )}
          </button>
        </div>

        {!startDate || !endDate ? (
          <div className="flex flex-col items-center justify-center p-12 bg-slate-900/20 border border-slate-800 rounded-3xl text-center">
            <CalendarIcon className="w-16 h-16 text-amber-500 mb-4 animate-bounce" />
            <h4 className="text-md font-bold text-white mb-2">
              {activeTab === 'monitoring' 
                ? 'يرجى تحديد فترة زمنية (من - إلى) أولاً لعرض خريطة التتبع وسجل الحضور 📅' 
                : 'يرجى تحديد فترة زمنية (من - إلى) أولاً لعرض قرارات الغياب والتأخير المعلقة 📅'}
            </h4>
            <p className="text-slate-400 text-xs">اختر التاريخ من شريط التحكم أعلاه للبدء</p>
          </div>
        ) : activeTab === 'monitoring' ? (
          <>
            {/* Bottom index indicator logs */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
              <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
                <span className="text-[10px] text-slate-400 block mb-1">الموظفين الحاضرين بالخريطة</span>
                <span className="text-xl font-black text-teal-400">{attendanceLogs.length}</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
                <span className="text-[10px] text-slate-400 block mb-1">رصد التزييف الجغرافي (Mock)</span>
                <span className="text-xl font-black text-rose-500">{securityLogs.length}</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
                <span className="text-[10px] text-slate-400 block mb-1">سياجات جغرافية نشطة</span>
                <span className="text-xl font-black text-blue-400">{geofenceZones.length}</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
                <span className="text-[10px] text-slate-400 block mb-1">نسبة الأمان للمؤسسة</span>
                <span className="text-xl font-black text-emerald-400">
                  {securityLogs.length === 0 ? '100%' : '94.2%'}
                </span>
              </div>
            </div>

            {/* Advanced Attendance Table */}
            <div className="mb-8">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
                  <Clock className="w-5 h-5 text-teal-400" />
                  <span>سجل الحضور والانصراف المتقدم</span>
                </h3>
                <button
                  onClick={handleExportExcel}
                  className="flex items-center gap-2 py-2 px-4 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-emerald-500/10 cursor-pointer"
                >
                  <Download className="w-4 h-4" />
                  <span className="hidden sm:inline">تصدير Excel</span>
                </button>
              </div>
              
              <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
                <table className="w-full text-sm text-right">
                  <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
                    <tr>
                      <th className="px-4 py-4 font-bold">اسم الموظف</th>
                      <th className="px-4 py-4 font-bold">التاريخ</th>
                      <th className="px-4 py-4 font-bold">وقت الدخول</th>
                      <th className="px-4 py-4 font-bold">وقت الخروج</th>
                      <th className="px-4 py-4 font-bold">ساعات العمل</th>
                      <th className="px-4 py-4 font-bold text-center">الإجراءات</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60 bg-slate-950/30">
                    {attendanceRows.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="px-4 py-12 text-center text-slate-500 text-xs">
                          لا توجد سجلات حضور لهذه الفترة
                        </td>
                      </tr>
                    ) : (
                      attendanceRows.map((log) => (
                        <tr key={log.id} className={`hover:bg-slate-900/40 transition-colors ${log.is_virtual ? 'bg-rose-500/5' : ''}`}>
                          <td className="px-4 py-3 font-bold text-white text-xs flex items-center gap-2">
                            {log.employees?.full_name || 'موظف'}
                            {log.is_virtual && <span className="bg-rose-500/20 text-rose-400 text-[9px] px-1.5 py-0.5 rounded border border-rose-500/30">لم يبصم (غائب)</span>}
                          </td>
                          <td className="px-4 py-3 text-slate-400 text-xs font-mono">{log.work_date}</td>
                          <td className="px-4 py-3 text-emerald-400 text-xs font-mono">
                            {log.check_in_time ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-'}
                          </td>
                          <td className="px-4 py-3 text-rose-400 text-xs font-mono">
                            {log.check_out_time ? new Date(log.check_out_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-'}
                          </td>
                          <td className="px-4 py-3 text-slate-300 text-xs font-bold">
                            {formatHours(log.check_in_time, log.check_out_time)}
                          </td>
                          <td className="px-4 py-3 flex items-center justify-center gap-2">
                            {!log.is_virtual && (
                              <>
                                <button
                                  onClick={() => {
                                    setEditingRecord(log);
                                    setEditCheckIn(formatTimeInputValue(log.check_in_time));
                                    setEditCheckOut(formatTimeInputValue(log.check_out_time));
                                  }}
                                  className="p-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 rounded-lg text-teal-400 transition-colors cursor-pointer"
                                  title="تعديل وقت الدخول/الخروج"
                                >
                                  <Edit className="w-3.5 h-3.5" />
                                </button>
                                {!log.check_out_time && (
                                  <button
                                    onClick={() => handleForceCheckout(log.id)}
                                    className="p-1.5 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 rounded-lg text-rose-400 transition-colors cursor-pointer flex items-center gap-1"
                                    title="تسجيل خروج إجباري الآن"
                                  >
                                    <LogOut className="w-3.5 h-3.5" />
                                  </button>
                                )}
                              </>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Dynamic Map Component */}
            <div className="mt-8 pt-8 border-t border-slate-800/80 space-y-6">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                  <h3 className="text-lg font-extrabold text-white flex items-center gap-2 mb-1">
                    <Map className="w-5 h-5 text-teal-400" />
                    <span>خريطة التتبع المباشر وحركة الموظفين</span>
                  </h3>
                  <p className="text-[11px] text-slate-400">تتبع مسار حركة الموظفين ميدانياً على الخريطة في الوقت الفعلي أثناء ساعات العمل</p>
                </div>

                <div className="flex flex-wrap items-center gap-3 bg-slate-950/40 p-2 border border-slate-800 rounded-2xl">
                  {/* Select Employee to Track */}
                  <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5">
                    <Users className="w-3.5 h-3.5 text-teal-400" />
                    <select
                      value={selectedEmployeeForTrail || ''}
                      onChange={(e) => {
                        const val = e.target.value;
                        setSelectedEmployeeForTrail(val || null);
                      }}
                      className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
                    >
                      <option value="" className="bg-slate-900">اختر موظف لتتبع مساره...</option>
                      {attendanceLogs.map((log) => (
                        <option key={log.employee_id} value={log.employee_id} className="bg-slate-900">
                          {log.employees?.full_name}
                        </option>
                      ))}
                    </select>
                  </div>

                  {selectedEmployeeForTrail && (
                    <label className="flex items-center gap-2 cursor-pointer bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 select-none">
                      <input
                        type="checkbox"
                        checked={liveTrackingActive}
                        onChange={(e) => setLiveTrackingActive(e.target.checked)}
                        className="rounded border-slate-800 text-teal-500 focus:ring-teal-500 bg-slate-950 w-3.5 h-3.5"
                      />
                      <span className="text-xs text-slate-300 font-bold">بث مباشر متواصل (أونلاين) 🟢</span>
                    </label>
                  )}
                </div>
              </div>

              {selectedEmployeeForTrail && trailCoordinates.length > 0 && (
                <div className="p-4 bg-teal-950/10 border border-teal-500/10 rounded-2xl flex justify-between items-center text-xs animate-glass">
                  <div className="space-y-1">
                    <p className="text-slate-300">
                      • إجمالي نقاط الحركة المرصودة اليوم: <strong className="text-white font-bold">{trailCoordinates.length} نقطة تتبع</strong>
                    </p>
                    <p className="text-[10px] text-slate-400">
                      * يربط الخط المتقطع الأزرق بين مسار تنقلات الموظف منذ بصمة الحضور وحتى اللحظة.
                    </p>
                  </div>
                  {liveTrackingActive && (
                    <span className="flex items-center gap-1.5 text-xs text-teal-400 font-black animate-pulse">
                      <span className="w-2.5 h-2.5 bg-teal-400 rounded-full"></span>
                      <span>تحديث فوري نشط...</span>
                    </span>
                  )}
                </div>
              )}

              <div className="flex-grow min-h-[500px] relative rounded-2xl overflow-hidden border border-slate-800/60">
                <MapComponent 
                  markers={markers}
                  polygons={polygons}
                  polylines={
                    selectedEmployeeForTrail && trailCoordinates.length >= 2
                      ? [{ coords: trailCoordinates, color: '#3B82F6', weight: 4.5 }]
                      : []
                  }
                  center={selectedCenter}
                  zoom={selectedZoom}
                />
              </div>
            </div>
          </>
        ) : (
          /* Decisions Tab View */
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h4 className="text-md font-bold text-white">إجراءات المخالفات وقرارات الخصم من الراتب</h4>
                <p className="text-[11px] text-slate-400">حدد «تطبيق» لتخصيم القيمة من صافي الراتب، أو «تجاهل» للعفو عن الموظف دون تأثر راتبه</p>
              </div>
            </div>

            <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
              <table className="w-full text-sm text-right">
                <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
                  <tr>
                    <th className="px-4 py-4 font-bold w-12 text-center">✓</th>
                    <th className="px-4 py-4 font-bold">الموظف</th>
                    <th className="px-4 py-4 font-bold">المدة</th>
                    <th className="px-4 py-4 font-bold">نوع المخالفة</th>
                    <th className="px-4 py-4 font-bold">الخصم (د.ع)</th>
                    <th className="px-4 py-4 font-bold">السبب</th>
                    <th className="px-4 py-4 font-bold text-center">القرار</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 bg-slate-950/30 text-xs">
                  {decisionsList.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-12 text-center text-slate-500 text-xs">
                        لا توجد غيابات أو تأخيرات مرصودة للتاريخ المختار
                      </td>
                    </tr>
                  ) : (
                    decisionsList.map((item, idx) => {
                      const rowKey = `${item.employee.id}_${item.type}_${item.date}`;
                      const currentReason = selectedReasons[rowKey] || item.reason;

                      return (
                        <tr key={idx} className="hover:bg-slate-900/40 transition-colors">
                          <td className="px-4 py-4 text-center">
                            <span className="text-[10px] bg-slate-850 px-2 py-0.5 rounded text-slate-400 font-mono">
                              {idx + 1}
                            </span>
                          </td>
                          <td className="px-4 py-4">
                            <div className="flex flex-col">
                              <span className="font-bold text-white">{item.employee.full_name}</span>
                              <span className="text-[10px] text-slate-400">
                                {item.employee.departments?.name || 'بدون قسم'} • {item.time !== '-' ? `البصمة: ${item.time}` : 'غياب كامل اليوم'}
                              </span>
                            </div>
                          </td>
                          <td className="px-4 py-4 text-slate-300 font-bold font-mono">
                            {item.duration}
                          </td>
                          <td className="px-4 py-4">
                            <span className={`px-2.5 py-0.5 rounded-full text-[10px] font-bold ${
                              item.type === 'late' ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                            }`}>
                              {item.typeName}
                            </span>
                          </td>
                          <td className="px-4 py-4">
                            <input 
                              type="number"
                              value={selectedAmounts[rowKey] !== undefined ? selectedAmounts[rowKey] : (item.suggestedAmount || '')}
                              onChange={(e) => setSelectedAmounts(prev => ({ ...prev, [rowKey]: e.target.value }))}
                              className="bg-slate-900 text-xs text-white border border-slate-700/60 rounded-xl px-2.5 py-1.5 outline-none w-24 mb-2"
                              placeholder="مبلغ الخصم"
                            />
                          </td>
                          <td className="px-4 py-4">
                            <input
                              type="text"
                              value={currentReason}
                              onChange={(e) => setSelectedReasons(prev => ({ ...prev, [rowKey]: e.target.value }))}
                              className="bg-slate-900 text-xs text-white border border-slate-700/60 rounded-xl px-2.5 py-1.5 outline-none w-full"
                              placeholder="اكتب سبب الخصم هنا..."
                            />
                          </td>
                          <td className="px-4 py-4 text-center">
                            <div className="flex items-center justify-center gap-2">
                              {/* Apply button */}
                              <button
                                onClick={() => {
                                  const amt = Number(selectedAmounts[rowKey] !== undefined ? selectedAmounts[rowKey] : item.suggestedAmount) || 0;
                                  handleDecision(item.employee, item.type, item.date, 'applied', item.id, currentReason, amt);
                                }}
                                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                                  item.deductionStatus === 'applied'
                                    ? 'bg-emerald-600 text-white shadow-md shadow-emerald-500/10'
                                    : 'bg-slate-800 text-slate-400 hover:bg-emerald-600/20 hover:text-emerald-400 border border-slate-700'
                                }`}
                              >
                                تطبيق
                              </button>
                              
                              {/* Ignore button */}
                              <button
                                onClick={() => handleDecision(item.employee, item.type, item.date, 'ignored', item.id, currentReason, 0)}
                                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                                  item.deductionStatus === 'ignored'
                                    ? 'bg-rose-600 text-white shadow-md shadow-rose-500/10'
                                    : 'bg-slate-800 text-slate-400 hover:bg-rose-600/20 hover:text-rose-400 border border-slate-700'
                                }`}
                              >
                                تجاهل
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

      </div>

      {/* Edit Modal */}
      {editingRecord && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-bold text-white">تعديل سجل الحضور</h3>
              <button onClick={() => setEditingRecord(null)} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
            </div>
            
            <form onSubmit={handleUpdateTimes} className="space-y-4">
              <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
                <strong>الموظف:</strong> {editingRecord.employees?.full_name} <br/>
                <strong>التاريخ:</strong> {editingRecord.work_date}
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">وقت تسجيل الدخول</label>
                <input 
                  type="time" 
                  value={editCheckIn}
                  onChange={(e) => setEditCheckIn(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">وقت تسجيل الخروج</label>
                <input 
                  type="time" 
                  value={editCheckOut}
                  onChange={(e) => setEditCheckOut(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
              >
                {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                <span>حفظ التعديلات</span>
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Manual Attendance Modal */}
      {showManualModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl animate-glass">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-bold text-white">تسجيل حضور وانصراف يدوي ✍️</h3>
              <button onClick={() => setShowManualModal(false)} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
            </div>
            
            <form onSubmit={handleManualAttendanceSubmit} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">الموظف</label>
                <select
                  required
                  value={manualEmpId}
                  onChange={(e) => setManualEmpId(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-xs focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all cursor-pointer"
                >
                  <option value="">-- اختر الموظف --</option>
                  {employees.map(emp => (
                    <option key={emp.id} value={emp.id} className="bg-slate-900">{emp.full_name}</option>
                  ))}
                </select>
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">تاريخ الدوام (YYYY-MM-DD)</label>
                <input 
                  type="text" 
                  value={manualDate}
                  onChange={(e) => setManualDate(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all font-mono"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">وقت الدخول</label>
                <input 
                  type="time" 
                  value={manualCheckIn}
                  onChange={(e) => setManualCheckIn(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">وقت الخروج</label>
                <input 
                  type="time" 
                  value={manualCheckOut}
                  onChange={(e) => setManualCheckOut(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 focus:ring-1 focus:ring-teal-500/50 outline-none transition-all"
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
              >
                {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                <span>تسجيل الحضور اليدوي 🎯</span>
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
