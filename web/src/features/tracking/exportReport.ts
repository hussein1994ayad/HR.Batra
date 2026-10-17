// تصدير كشف المراقبة والانضباط إلى Excel.

import { downloadExcel, recordsToRows, spanningCell } from '@/lib/excel';
import type { Branch, LeaveRequest } from '@/lib/db-types';
import { formatClock } from '@/lib/format';
import { formatHours, isDateWithinRange } from './logic';
import type { AttendanceRow, Decision, MockGpsAttempt, TrackedEmployee } from './types';

export async function exportDisciplineReport(input: {
  rows: AttendanceRow[];
  decisionsList: Decision[];
  leaveRequests: LeaveRequest[];
  securityLogs: MockGpsAttempt[];
  branches: Branch[];
  employees: TrackedEmployee[];
  startDate: string;
  endDate: string;
  selectedBranch: string;
  selectedEmployee: string;
}): Promise<void> {
  const {
    rows, decisionsList, leaveRequests, securityLogs, branches, employees,
    startDate, endDate, selectedBranch, selectedEmployee,
  } = input;
  const fullList = rows;
  
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
      // المبلغ كما يحسبه محرّك الرواتب
      if (dec.deductionStatus === 'applied') {
        decStatusStr = 'تم اعتماد الخصم ✅';
        const amt = dec.suggestedAmount || 0;
        decAmountStr = `${Number(amt).toLocaleString('ar-IQ')} د.ع`;
      } else if (dec.deductionStatus === 'ignored') {
        decStatusStr = 'معفى من الخصم 🔓';
        decAmountStr = '0 د.ع (إعفاء)';
      } else {
        decStatusStr = 'بانتظار القرار ⏳';
        const amt = dec.suggestedAmount || 0;
        decAmountStr = amt > 0 ? `${Number(amt).toLocaleString('ar-IQ')} د.ع (عند الاعتماد)` : '-';
      }
    }

    // Find approved leave
    // نفس مقارنة صفحة الحضور (اليوم المحلي، مو تاريخ UTC)
    const leave = leaveRequests.find(l => l.employee_id === log.employee_id && isDateWithinRange(log.work_date, l.start_date, l.end_date));

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
      'وقت الدخول الفعلي': log.check_in_time ? formatClock(log.check_in_time) : '-',
      'وقت الخروج الفعلي': log.check_out_time ? formatClock(log.check_out_time) : '-',
      'ساعات العمل': formatHours(log.check_in_time, log.check_out_time),
      'حالة الدوام': attendanceStatus,
      'مدة التأخير': delayStr,
      'حالة الخصم': decStatusStr,
      'قيمة الخصم (د.ع)': decAmountStr,
      'ملاحظات الانضباط والتنبيهات الذكية': notesStr
    };
  });

  // 1. Title block: four lines, each merged across the 13 columns (A1:M1 ... A4:M4), then a blank spacer row
  const title = [
    "كشف المراقبة والانضباط الوظيفي التفصيلي الموحد - شركة بترى",
    `الفترة المشمولة بالتقرير: من ${startDate} إلى ${endDate}`,
    `فرع المؤسسة المصفى: ${selectedBranch === 'all' ? 'جميع الفروع' : (branches.find(b => b.id === selectedBranch)?.name || '')} | الموظف المصفى: ${selectedEmployee === 'all' ? 'جميع الموظفين' : (employees.find(e => e.id === selectedEmployee)?.full_name || '')}`,
    `تاريخ ووقت استخراج التقرير: ${new Date().toLocaleString('ar-IQ', { hour12: true })}`,
  ];

  // 2. The main table starts at A6 (header row, then one row per day)
  const data = [...title.map((line) => [spanningCell(line, 13)]), [null], ...recordsToRows(excelData)];

  // 3. Right-to-left layout for Arabic readers, and column widths that prevent clipping
  const columns = [
    6,   // ت
    28,  // اسم الموظف
    20,  // الفرع
    15,  // تاريخ الدوام
    12,  // اليوم
    16,  // وقت الدخول الفعلي
    16,  // وقت الخروج الفعلي
    16,  // ساعات العمل
    20,  // حالة الدوام
    15,  // مدة التأخير
    20,  // حالة الخصم
    22,  // قيمة الخصم (د.ع)
    45,  // ملاحظات الانضباط والتنبيهات الذكية
  ].map((width) => ({ width }));

  await downloadExcel(`تقرير_الانضباط_والتتبع_شركة_بترى_${startDate}_الى_${endDate}.xlsx`, [
    { name: "كشف الانضباط والتتبع", data, columns, rightToLeft: true },
  ]);
}
