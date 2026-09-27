// =========================================================================
// منطق صفحة المراقبة — دوال نقية بدون React أو Supabase (منقولة كما هي من الصفحة)
// =========================================================================

import type { AttendanceRecord, LeaveRequest, WorkSchedule } from '@/lib/db-types';
import { formatLateDurationArabic } from '@/lib/dates';
import { resolveWorkSchedule } from '@/lib/schedules';
import type {
  AttendanceRow, Decision, DetectedStop, MapMarker, MockGpsAttempt, RawPoint, RawZone, TrackedEmployee,
} from './types';

type TrailPoint = { latitude: number | string; longitude: number | string; timestamp: string };

/**
 * مسار حركة الموظف: يحذف النقاط المتكررة (~10م) ويكتشف التوقفات (أقل من ~50م لمدة 5 دقائق فأكثر).
 */
export function analyzeTrail(data: TrailPoint[]): { coords: [number, number][]; stops: DetectedStop[] } {
  const rawCoords: [number, number][] = data.map(item => [Number(item.latitude), Number(item.longitude)]);

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



  return { coords: filteredCoords, stops };
}

/** علامات الخريطة: الحضور، محاولات التزييف، آخر موقع للموظف المتتبَّع، والتوقفات. */
export function buildMapMarkers(input: {
  attendanceLogs: AttendanceRecord[];
  securityLogs: MockGpsAttempt[];
  selectedEmployeeForTrail: string | null;
  trailCoordinates: [number, number][];
  detectedStops: DetectedStop[];
}): MapMarker[] {
  const { attendanceLogs, securityLogs, selectedEmployeeForTrail, trailCoordinates, detectedStops } = input;
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
}

/** مضلعات السياج الجغرافي بعد توحيد أشكال الإحداثيات المخزنة. */
export function parseZonePolygons(geofenceZones: RawZone[]): { name: string; coords: [number, number][] }[] {
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
}

/** مخالفات الغياب والتأخير لكل يوم عمل ضمن الفترة (تشمل الغياب "الافتراضي" لمن لم يبصم). */
export function buildDecisions(input: {
  startDate: string;
  endDate: string;
  employees: TrackedEmployee[];
  workSchedules: WorkSchedule[];
  leaveRequests: LeaveRequest[];
  attendanceLogs: AttendanceRecord[];
  selectedBranch: string;
  selectedEmployee: string;
}): Decision[] {
  const {
    startDate, endDate, employees, workSchedules, leaveRequests, attendanceLogs, selectedBranch, selectedEmployee,
  } = input;
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
}

/** سجلات الحضور + صفوف غياب افتراضية للموظفين الذين لم يبصموا في يوم عمل. */
export function buildAttendanceRows(attendanceLogs: AttendanceRecord[], decisions: Decision[]): AttendanceRow[] {
  return [
    ...attendanceLogs.map(log => ({ ...log, is_virtual: false })),
    ...decisions.filter(d => d.type === 'virtual_absent').map(d => ({
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
}

/** مدة الدوام بين الدخول والخروج: "8 س و 15 د". */
export const formatHours = (checkIn?: string | null, checkOut?: string | null) => {
  if (!checkIn || !checkOut) return '-';
  const diffMs = new Date(checkOut).getTime() - new Date(checkIn).getTime();
  if (diffMs <= 0) return '-';
  const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
  const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
  return `${diffHrs} س و ${diffMins} د`;
};

/** قيمة حقل <input type="time"> من طابع زمني. */
export const formatTimeInputValue = (dateString?: string | null) => {
  if (!dateString) return '';
  const d = new Date(dateString);
  const h = d.getHours().toString().padStart(2, '0');
  const m = d.getMinutes().toString().padStart(2, '0');
  return `${h}:${m}`;
};

/** مفتاح صف القرار (يُستعمل لحفظ المبلغ والسبب المعدّلين). */
export const decisionKey = (d: Pick<Decision, 'employee' | 'type' | 'date'>) => `${d.employee.id}_${d.type}_${d.date}`;
