'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import MapComponent from '@/components/MapComponent';
import { 
  MapPin, 
  Users, 
  ShieldAlert, 
  CheckCircle,
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

export default function TrackingPage() {
  const [loading, setLoading] = useState(true);
  const [attendanceLogs, setAttendanceLogs] = useState<any[]>([]);
  const [securityLogs, setSecurityLogs] = useState<any[]>([]);
  const [geofenceZones, setGeofenceZones] = useState<any[]>([]);
  const [selectedCenter, setSelectedCenter] = useState<[number, number]>([33.3152, 44.3661]); // Baghdad default
  const [selectedZoom, setSelectedZoom] = useState(12);

  const getLocalDateStr = () => {
    const d = new Date();
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().split('T')[0];
  };

  // New states for advanced attendance
  const [selectedDate, setSelectedDate] = useState(getLocalDateStr());
  const [editingRecord, setEditingRecord] = useState<any>(null);
  const [editCheckIn, setEditCheckIn] = useState('');
  const [editCheckOut, setEditCheckOut] = useState('');
  
  const [branches, setBranches] = useState<any[]>([]);
  const [selectedBranch, setSelectedBranch] = useState('all');

  // Manual attendance states
  const [employees, setEmployees] = useState<any[]>([]);
  const [showManualModal, setShowManualModal] = useState(false);
  const [manualEmpId, setManualEmpId] = useState('');
  const [manualDate, setManualDate] = useState(selectedDate);
  const [manualCheckIn, setManualCheckIn] = useState('09:00');
  const [manualCheckOut, setManualCheckOut] = useState('17:00');

  // Decisions states
  const [activeTab, setActiveTab] = useState<'monitoring' | 'decisions'>('monitoring');
  const [workSchedules, setWorkSchedules] = useState<any[]>([]);
  const [leaveRequests, setLeaveRequests] = useState<any[]>([]);
  const [selectedReasons, setSelectedReasons] = useState<Record<string, string>>({});
  const [selectedAmounts, setSelectedAmounts] = useState<Record<string, string>>({});
  
  // Live Trail States
  const [selectedEmployeeForTrail, setSelectedEmployeeForTrail] = useState<string | null>(null);
  const [trailCoordinates, setTrailCoordinates] = useState<[number, number][]>([]);
  const [liveTrackingActive, setLiveTrackingActive] = useState(false);

  useEffect(() => {
    fetchTrackingData(selectedDate, selectedBranch);
  }, [selectedDate, selectedBranch]);

  const fetchTrackingData = async (dateStr = selectedDate, branchId = selectedBranch) => {
    setLoading(true);
    try {
      const promises: any[] = [
        supabase.from('geofence_zones').select('*').eq('is_active', true),
        supabase.from('branches').select('*'),
        supabase.from('employees').select('id, full_name, branch_id, department_id, role, departments:departments!employees_department_id_fkey(name)').eq('is_active', true).order('full_name'),
        supabase.from('work_schedules').select('*'),
        supabase.from('leave_requests').select('*').eq('status', 'approved')
      ];

      // Only query attendance and mock attempts if date is selected
      if (dateStr) {
        promises.push(
          supabase.from('attendance').select('*, employees!employee_id(full_name, branch_id)').eq('work_date', dateStr),
          supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false })
        );
      }

      const results = await Promise.all(promises);

      const resZones = results[0];
      const resBranches = results[1];
      const resEmps = results[2];
      const resScheds = results[3];
      const resLeaves = results[4];

      if (resZones.data) setGeofenceZones(resZones.data);
      if (resBranches.data) setBranches(resBranches.data);
      if (resEmps.data) setEmployees(resEmps.data);
      if (resScheds.data) setWorkSchedules(resScheds.data);
      if (resLeaves.data) setLeaveRequests(resLeaves.data);

      if (dateStr) {
        const resAtt = results[5];
        const resMock = results[6];

        let filteredAtt = resAtt.data || [];
        if (branchId !== 'all') {
          filteredAtt = filteredAtt.filter((log: any) => log.employees?.branch_id === branchId);
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

  const fetchTrailData = async (employeeId: string, dateStr: string) => {
    try {
      const startOfDay = `${dateStr}T00:00:00.000Z`;
      const endOfDay = `${dateStr}T23:59:59.999Z`;

      const { data, error } = await supabase
        .from('location_tracking')
        .select('latitude, longitude, timestamp')
        .eq('employee_id', employeeId)
        .gte('timestamp', startOfDay)
        .lte('timestamp', endOfDay)
        .order('timestamp', { ascending: true });

      if (error) throw error;

      if (data) {
        const coords: [number, number][] = data.map((item: any) => [Number(item.latitude), Number(item.longitude)]);
        setTrailCoordinates(coords);
        if (coords.length > 0) {
          setSelectedCenter(coords[coords.length - 1]);
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
      return;
    }

    fetchTrailData(selectedEmployeeForTrail, selectedDate);

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
        (payload: any) => {
          const newLat = Number(payload.new.latitude);
          const newLng = Number(payload.new.longitude);
          if (newLat && newLng) {
            setTrailCoordinates(prev => [...prev, [newLat, newLng]]);
            setSelectedCenter([newLat, newLng]);
            toast.success('موقع جديد مستلم في الوقت المباشر! 📍');
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [selectedEmployeeForTrail, liveTrackingActive, selectedDate]);

  const handleUpdateTimes = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingRecord) return;
    
    try {
      setLoading(true);
      const checkInISO = editCheckIn ? new Date(`${selectedDate}T${editCheckIn}:00`).toISOString() : null;
      const checkOutISO = editCheckOut ? new Date(`${selectedDate}T${editCheckOut}:00`).toISOString() : null;
      
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
      fetchTrackingData(selectedDate);
    } catch (err) {
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
      fetchTrackingData(selectedDate);
    } catch (err: any) {
      toast.error(`حدث خطأ: ${err.message || err}`);
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
      fetchTrackingData(selectedDate);
    } catch (err) {
      toast.error('حدث خطأ أثناء تسجيل الخروج.');
    } finally {
      setLoading(false);
    }
  };

  const handleDecision = async (
    emp: any,
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

        const { error } = await supabase.from('attendance').insert({
          employee_id: emp.id,
          work_date: infractionDate,
          status: 'absent',
          deduction_status: status,
          deduction_reason: reason,
          branch_id: defaultBranchId
        });
        if (error) throw error;
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

      // Add a notification for the employee
      await supabase.from('notifications').insert({
        employee_id: emp.id,
        title: status === 'applied' ? 'تطبيق خصم مالي ⚠️' : 'إعفاء من الخصم المالي ✅',
        body: status === 'applied'
          ? `تقرر تطبيق الخصم المالي المترتب على ${type === 'late' ? 'التأخير الصباحي' : 'الغياب'} ليوم ${infractionDate}. السبب: ${reason}`
          : `تم إعفاؤك من الخصم المالي المترتب على ${type === 'late' ? 'التأخير الصباحي' : 'الغياب'} ليوم ${infractionDate}.`,
        type: 'attendance'
      });

      toast.success('تم حفظ القرار وإرسال إشعار للموظف بنجاح! 🔔');
      fetchTrackingData(selectedDate, selectedBranch);
    } catch (err: any) {
      toast.error(`حدث خطأ أثناء حفظ القرار: ${err.message || err}`);
    } finally {
      setLoading(false);
    }
  };

  const formatHours = (checkIn: string, checkOut: string) => {
    if (!checkIn || !checkOut) return '-';
    const diffMs = new Date(checkOut).getTime() - new Date(checkIn).getTime();
    if (diffMs <= 0) return '-';
    const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
    const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
    return `${diffHrs} س و ${diffMins} د`;
  };

  const formatTimeInputValue = (dateString: string | null) => {
    if (!dateString) return '';
    const d = new Date(dateString);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  };

  const handleExportExcel = () => {
    try {
      const fullList = [
        ...attendanceLogs,
        ...decisionsList.filter(d => d.type === 'virtual_absent').map(d => ({
          is_virtual: true,
          employee_id: d.employee.id,
          work_date: selectedDate,
          check_in_time: null,
          check_out_time: null,
          employees: d.employee
        }))
      ];
      
      const excelData = fullList.map(log => ({
        'اسم الموظف': log.employees?.full_name || 'غير محدد',
        'التاريخ': log.work_date,
        'وقت الدخول': log.check_in_time ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
        'وقت الخروج': log.check_out_time ? new Date(log.check_out_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
        'ساعات العمل': formatHours(log.check_in_time, log.check_out_time),
        'الحالة': log.is_virtual ? 'غياب' : (log.status === 'late' ? 'تأخير' : 'حضور')
      }));

      const worksheet = XLSX.utils.json_to_sheet(excelData);
      const workbook = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(workbook, worksheet, "تقرير الحضور");
      XLSX.writeFile(workbook, `تقرير_الحضور_${selectedDate}.xlsx`);
    } catch (err) {
      toast.error("حدث خطأ أثناء تصدير التقرير");
    }
  };

  const getMapMarkers = () => {
    const markers: any[] = [];
    attendanceLogs.forEach((log) => {
      if (log.check_in_lat && log.check_in_lng) {
        markers.push({
          lat: Number(log.check_in_lat),
          lng: Number(log.check_in_lng),
          isViolation: false,
          popupText: `
            <strong style="color: #0D9488; font-size: 13px;">حضور موظف فعال ✅</strong><br/>
            <strong>الاسم:</strong> ${log.employees?.full_name || 'موظف'}<br/>
            <strong>الوقت:</strong> ${new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}<br/>
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

    return markers;
  };

  const getMapPolygons = () => {
    return geofenceZones.map((zone) => {
      let coords: [number, number][] = [];
      if (zone.polygon_coordinates) {
        coords = Array.isArray(zone.polygon_coordinates) ? zone.polygon_coordinates : JSON.parse(zone.polygon_coordinates as string);
      }
      
      if (coords.length < 3 && zone.latitude && zone.longitude) {
        const offset = 0.003;
        coords = [
          [zone.latitude + offset, zone.longitude - offset],
          [zone.latitude + offset, zone.longitude + offset],
          [zone.latitude - offset, zone.longitude + offset],
          [zone.latitude - offset, zone.longitude - offset]
        ];
      }

      return {
        name: zone.name,
        coords: coords
      };
    });
  };

  // Compile infractions (absences and latenesses) for decisions
  const getDecisionsList = () => {
    if (!selectedDate) return [];
    const list: any[] = [];
    employees.forEach(emp => {
      if (selectedBranch !== 'all' && emp.branch_id !== selectedBranch) return;

      const attRecord = attendanceLogs.find(log => log.employee_id === emp.id);

      const empSched = workSchedules.find(s => s.employee_id === emp.id) || 
                       workSchedules.find(s => s.department_id === emp.department_id && !s.employee_id) ||
                       workSchedules.find(s => s.branch_id === emp.branch_id && !s.employee_id && !s.department_id);
      const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];
      
      const [year, month, day] = selectedDate.split('-');
      const dayObj = new Date(Number(year), Number(month) - 1, Number(day));
      const weekday = dayObj.getDay();
      const isWorkingDay = workDays.includes(weekday);

      if (!isWorkingDay) return;

      const isDateWithinRange = (dStr: string, startStr: string, endStr: string) => {
        if (!dStr || !startStr || !endStr) return false;
        const d = new Date(dStr).getTime();
        const s = new Date(startStr.split('T')[0]).getTime();
        const e = new Date(endStr.split('T')[0]).getTime();
        return d >= s && d <= e;
      };

      const leaveRecord = leaveRequests.find(l => l.employee_id === emp.id && isDateWithinRange(selectedDate, l.start_date, l.end_date));

      if (attRecord) {
        if (attRecord.status === 'late') {
          const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
          const checkIn = new Date(attRecord.check_in_time);
          const [h, m, s] = schedCheckIn.split(':').map(Number);
          const sched = new Date(checkIn);
          sched.setHours(h, m, s || 0, 0);
          const diffMs = checkIn.getTime() - sched.getTime();
          const lateMinutes = diffMs > 0 ? Math.floor(diffMs / (1000 * 60)) : 0;

          list.push({
            id: attRecord.id,
            type: 'late',
            employee: emp,
            date: selectedDate,
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
            date: selectedDate,
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
            date: selectedDate,
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
                onChange={(e) => setSelectedBranch(e.target.value)}
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
              <input 
                type="date" 
                value={selectedDate}
                onChange={(e) => setSelectedDate(e.target.value)}
                className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
              />
            </div>
            
            <button
              onClick={() => fetchTrackingData(selectedDate, selectedBranch)}
              className="flex items-center gap-2 py-2 px-4 bg-slate-800 hover:bg-slate-750 text-white rounded-xl text-xs font-bold transition-all border border-slate-700/60 cursor-pointer"
            >
              <RefreshCw className="w-4 h-4" />
              <span className="hidden sm:inline">تحديث</span>
            </button>

            <button
              onClick={() => {
                setManualDate(selectedDate);
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

        {!selectedDate ? (
          <div className="flex flex-col items-center justify-center p-12 bg-slate-900/20 border border-slate-800 rounded-3xl text-center">
            <CalendarIcon className="w-16 h-16 text-amber-500 mb-4 animate-bounce" />
            <h4 className="text-md font-bold text-white mb-2">
              {activeTab === 'monitoring' 
                ? 'يرجى تحديد تاريخ أولاً لعرض خريطة التتبع وسجل الحضور 📅' 
                : 'يرجى تحديد تاريخ أولاً لعرض قرارات الغياب والتأخير المعلقة 📅'}
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
                    {[
                      ...attendanceLogs,
                      ...decisionsList.filter(d => d.type === 'virtual_absent').map(d => ({
                        id: `virtual_${d.employee.id}`,
                        is_virtual: true,
                        employee_id: d.employee.id,
                        work_date: selectedDate,
                        check_in_time: null,
                        check_out_time: null,
                        employees: d.employee
                      }))
                    ].length === 0 ? (
                      <tr>
                        <td colSpan={6} className="px-4 py-12 text-center text-slate-500 text-xs">
                          لا توجد سجلات حضور لهذا اليوم
                        </td>
                      </tr>
                    ) : (
                      [
                        ...attendanceLogs,
                        ...decisionsList.filter(d => d.type === 'virtual_absent').map(d => ({
                          id: `virtual_${d.employee.id}`,
                          is_virtual: true,
                          employee_id: d.employee.id,
                          work_date: selectedDate,
                          check_in_time: null,
                          check_out_time: null,
                          employees: d.employee
                        }))
                      ].map((log) => (
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
                <p className="text-[11px] text-slate-400">حدد "تطبيق" لتخصيم القيمة من صافي الراتب، أو "تجاهل" للعفو عن الموظف دون تأثر راتبه</p>
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
                <strong>التاريخ:</strong> {selectedDate}
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
