// تصدير كشف المراقبة والانضباط إلى Excel.

import * as XLSX from 'xlsx';
import type { Branch, LeaveRequest } from '@/lib/db-types';
import { decisionKey, formatHours } from './logic';
import type { AttendanceRow, Decision, MockGpsAttempt, TrackedEmployee } from './types';

export function exportDisciplineReport(input: {
  rows: AttendanceRow[];
  decisionsList: Decision[];
  selectedAmounts: Record<string, string>;
  leaveRequests: LeaveRequest[];
  securityLogs: MockGpsAttempt[];
  branches: Branch[];
  employees: TrackedEmployee[];
  startDate: string;
  endDate: string;
  selectedBranch: string;
  selectedEmployee: string;
}): void {
  const {
    rows, decisionsList, selectedAmounts, leaveRequests, securityLogs, branches, employees,
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
      // نفس مفتاح المبلغ المستعمل في جدول القرارات
      const rowKey = decisionKey(dec);
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
}
