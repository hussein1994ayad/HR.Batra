'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { resolveWorkSchedule } from '@/lib/schedules';
import { errorMessage } from '@/lib/error-utils';
import type {
  AttendanceRecord, BonusDeduction, Branch, Employee, LeaveRequest, LoanInstallment, SalarySlip, WorkSchedule,
} from '@/lib/db-types';
import { 
  Banknote, 
  Search, 
  Building, 
  Calendar as CalendarIcon, 
  Plus, 
  TrendingUp, 
  TrendingDown, 
  CheckCircle,
  Printer,
  Loader2,
  CalendarRange,
  Info,
  Clock,
  X,
  Bell,
  Archive
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

const getCycleDates = (monthStr: string, startDay: number = 25, endDay: number = 24) => {
  if (!monthStr) return { start: '', end: '' };
  const [year, month] = monthStr.split('-').map(Number);

  // Get last day of selected month
  const lastDaySelected = new Date(year, month, 0).getDate();

  if (startDay <= endDay) {
    // Same calendar month cycle (e.g. 1st to 30th/31st)
    const actualStartDay = Math.min(startDay, lastDaySelected);
    const actualEndDay = Math.min(endDay, lastDaySelected);

    const start = `${year}-${month.toString().padStart(2, '0')}-${actualStartDay.toString().padStart(2, '0')}`;
    const end = `${year}-${month.toString().padStart(2, '0')}-${actualEndDay.toString().padStart(2, '0')}`;
    return { start, end };
  } else {
    // Cross-month cycle (starts in previous month, ends in selected month, e.g. 25th to 24th)
    const prevMonthDate = new Date(year, month - 2, 1);
    const prevYear = prevMonthDate.getFullYear();
    const prevMonthNum = prevMonthDate.getMonth() + 1;
    const lastDayPrev = new Date(prevYear, prevMonthNum, 0).getDate();

    const actualStartDay = Math.min(startDay, lastDayPrev);
    const actualEndDay = Math.min(endDay, lastDaySelected);

    const start = `${prevYear}-${prevMonthNum.toString().padStart(2, '0')}-${actualStartDay.toString().padStart(2, '0')}`;
    const end = `${year}-${month.toString().padStart(2, '0')}-${actualEndDay.toString().padStart(2, '0')}`;
    return { start, end };
  }
};

// قيد يُنشأ مع كشف الراتب داخل approve_salary_slip
// سطر في تفصيل الحضور اليومي لموظف ضمن كشف الراتب
type DetailLog = {
  date: string;
  status: string;
  time: string;
  note: string;
  isAbsenceDay: boolean;
  isExcused?: boolean;
};

type SlipAdjustment = {
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
  issue_date: string;
  skip_if_exists: boolean;
};

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

const getBaghdadMinutesFromIso = (isoStr: string): number => {
  try {
    const d = new Date(isoStr);
    const utcHours = d.getUTCHours();
    const utcMins = d.getUTCMinutes();
    // Iraq / Baghdad is UTC+3
    const baghdadHours = (utcHours + 3) % 24;
    return baghdadHours * 60 + utcMins;
  } catch {
    return 0;
  }
};

const parseScheduleMinutes = (timeStr: string = '09:00:00'): number => {
  const parts = timeStr.split(':').map(Number);
  return (parts[0] || 0) * 60 + (parts[1] || 0);
};

export default function PayrollPage() {
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [sendingNotifs, setSendingNotifs] = useState(false);
  
  // صف محسوب في جدول الرواتب (بيانات الموظف + الحضور + الخصومات)
  type PayrollRow = (typeof processedPayroll)[number];

  // Data States
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [branches, setBranches] = useState<Pick<Branch, 'id' | 'name'>[]>([]);
  const [bonusesAndDeductions, setBonusesAndDeductions] = useState<BonusDeduction[]>([]);
  const [loanInstallments, setLoanInstallments] = useState<LoanInstallment[]>([]);
  const [attendanceLogs, setAttendanceLogs] = useState<AttendanceRecord[]>([]);
  const [leaveRequests, setLeaveRequests] = useState<LeaveRequest[]>([]);
  const [workSchedules, setWorkSchedules] = useState<WorkSchedule[]>([]);
  const [existingSlips, setExistingSlips] = useState<SalarySlip[]>([]);
  const [archivedMonths, setArchivedMonths] = useState<string[]>([]);
  
  // Filter States
  const [selectedMonth, setSelectedMonth] = useState(() => {
    const d = new Date();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    return `${d.getFullYear()}-${m}`;
  });
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    return getCycleDates(`${d.getFullYear()}-${m}`).start;
  });
  const [endDate, setEndDate] = useState(() => {
    const d = new Date();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    return getCycleDates(`${d.getFullYear()}-${m}`).end;
  });
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedBranch, setSelectedBranch] = useState('all');

  // Overrides State: Record<employeeId, { bonuses?: number, attendanceDeductions?: number, otherDeductions?: number }>
  const [payrollOverrides, setPayrollOverrides] = useState<Record<string, { bonuses?: number, attendanceDeductions?: number, otherDeductions?: number }>>({});
  const [editingCell, setEditingCell] = useState<{ employeeId: string, field: 'bonuses' | 'attendanceDeductions' | 'otherDeductions', currentValue: number } | null>(null);

  // Modal States
  const [showAddBDModal, setShowAddBDModal] = useState(false);
  const [selectedEmpForBD, setSelectedEmpForBD] = useState<Employee | null>(null);
  const [bdType, setBdType] = useState<'bonus' | 'deduction'>('bonus');
  const [bdAmount, setBdAmount] = useState<number>(0);
  const [bdReason, setBdReason] = useState('');

  // Attendance Breakdown Modal State (Stores the selected employee's ID)
  const [selectedEmpIdForBreakdown, setSelectedEmpIdForBreakdown] = useState<string | null>(null);

  // Excused days state: Record<employeeId, array of excused dates (YYYY-MM-DD)>
  const [excusedDays, setExcusedDays] = useState<Record<string, string[]>>({});
  const [showBulkModal, setShowBulkModal] = useState(false);
  const [cycleStartDay, setCycleStartDay] = useState(25);
  const [cycleEndDay, setCycleEndDay] = useState(24);


  const saveOverride = (employeeId: string, field: 'bonuses' | 'attendanceDeductions' | 'otherDeductions', value: number) => {
    setPayrollOverrides(prev => {
      const empOverrides = prev[employeeId] || {};
      return {
        ...prev,
        [employeeId]: {
          ...empOverrides,
          [field]: value
        }
      };
    });
    setEditingCell(null);
    toast.success('تم تعديل القيمة وتحديث صافي الراتب! 💸');
  };

  const clearOverride = (employeeId: string, field: 'bonuses' | 'attendanceDeductions' | 'otherDeductions') => {
    setPayrollOverrides(prev => {
      const empOverrides = { ...prev[employeeId] };
      delete empOverrides[field];
      const updated = { ...prev };
      if (Object.keys(empOverrides).length === 0) {
        delete updated[employeeId];
      } else {
        updated[employeeId] = empOverrides;
      }
      return updated;
    });
    setEditingCell(null);
    toast.success('تمت استعادة القيمة التلقائية المحتسبة! 🔄');
  };

  const renderEditableCell = (emp: PayrollRow, field: 'bonuses' | 'attendanceDeductions' | 'otherDeductions', displayValue: number, colorClass: string, prefixSign: string = '') => {
    const isEditing = editingCell && editingCell.employeeId === emp.id && editingCell.field === field;
    const empOverrides = payrollOverrides[emp.id] || {};
    const isOverridden = empOverrides[field] !== undefined;

    return (
      <div className="relative inline-block">
        <button
          onClick={() => {
            if (emp.isIssued) {
              toast.error('الراتب معتمد ومقفل ولا يمكن تعديله 🔒');
              return;
            }
            setEditingCell({
              employeeId: emp.id,
              field: field,
              currentValue: displayValue
            });
          }}
          className={`font-bold border-b border-dashed border-slate-700 hover:border-teal-500 hover:text-teal-300 transition-colors cursor-pointer outline-none select-none ${colorClass} ${isOverridden ? 'bg-amber-500/10 px-2 py-1 rounded-xl border-amber-500/30 hover:border-amber-400' : ''}`}
          title="اضغط لتعديل القيمة يدوياً"
        >
          {displayValue > 0 ? `${prefixSign}${displayValue.toLocaleString()} د.ع` : '-'}
          {isOverridden && <span className="text-[9px] text-amber-400 font-black mr-1" title="معدل يدوياً">*</span>}
        </button>

        {isEditing && (
          <div className="absolute z-50 bottom-full mb-2 right-1/2 translate-x-1/2 bg-slate-900 border border-slate-800 rounded-3xl p-4 shadow-2xl w-48 text-right space-y-3 animate-glass font-sans">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-indigo-500 rounded-t-3xl"></div>
            
            <h5 className="text-[10px] font-bold text-slate-400">
              {field === 'bonuses' ? 'تعديل المكافآت يدوياً' : 
               field === 'attendanceDeductions' ? 'تعديل خصومات الدوام والغياب' : 
               'تعديل الخصومات الأخرى'}
            </h5>
            
            <input 
              type="number" 
              defaultValue={displayValue}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2 text-xs text-white outline-none font-bold text-left"
              dir="ltr"
              autoFocus
              id="inline-edit-input"
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  saveOverride(emp.id, field, Number((e.target as HTMLInputElement).value));
                }
                if (e.key === 'Escape') {
                  setEditingCell(null);
                }
              }}
            />
            
            <div className="flex gap-1.5 justify-end">
              {isOverridden && (
                <button 
                  type="button" 
                  onClick={() => clearOverride(emp.id, field)}
                  className="text-[9px] text-amber-500 hover:text-amber-400 font-bold ml-auto"
                >
                  تلقائي 🔄
                </button>
              )}
              <button 
                type="button" 
                onClick={() => setEditingCell(null)}
                className="px-2 py-1 text-[10px] text-slate-400 hover:text-white"
              >
                إلغاء
              </button>
              <button 
                type="button"
                onClick={() => {
                  const input = document.getElementById('inline-edit-input') as HTMLInputElement;
                  if (input) {
                    saveOverride(emp.id, field, Number(input.value));
                  }
                }}
                className="px-3 py-1 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-[10px] font-bold shadow-md cursor-pointer active:scale-95 transition-all"
              >
                حفظ
              </button>
            </div>
          </div>
        )}
      </div>
    );
  };

  const handleMonthChange = (monthVal: string) => {
    setSelectedMonth(monthVal);
    const { start, end } = getCycleDates(monthVal, cycleStartDay, cycleEndDay);
    setStartDate(start);
    setEndDate(end);
  };

  const fetchPayrollData = async () => {
    if (!startDate || !endDate) return;
    setLoading(true);
    try {
      // 0. Get Payroll Policy settings to dynamically check start/end days
      const { data: pp } = await supabase
        .from('system_settings')
        .select('*')
        .eq('key', 'payroll_policy')
        .maybeSingle();

      let currentStartDay = 25;
      let currentEndDay = 24;
      if (pp && pp.value) {
        currentStartDay = pp.value.cycle_start_day || 25;
        currentEndDay = pp.value.cycle_end_day || 24;
        setCycleStartDay(currentStartDay);
        setCycleEndDay(currentEndDay);
        
        // If current startDate or endDate doesn't match policy, update them
        const expectedDates = getCycleDates(selectedMonth, currentStartDay, currentEndDay);
        if (startDate !== expectedDates.start || endDate !== expectedDates.end) {
          setStartDate(expectedDates.start);
          setEndDate(expectedDates.end);
          return; // Let useEffect trigger fetch with correct dates
        }
      }

      // 1. Fetch all datasets concurrently using Promise.all
      const [
        resBrs,
        resEmps,
        resBds,
        resLoans,
        resAtt,
        resLvs,
        resScheds,
        resSlips,
        resArchived
      ] = await Promise.all([
        supabase.from('branches').select('id, name'),
        supabase.from('employees')
          .select('id, full_name, monthly_salary_iqd, future_salary_iqd, future_salary_month, branch_id, department_id, created_at, join_date, branches(name)')
          .eq('is_active', true)
          .order('full_name'),
        supabase.from('bonuses_deductions')
          .select('*')
          .gte('issue_date', startDate)
          .lte('issue_date', endDate),
        supabase.from('loan_installments')
          .select('*, loans!inner(employee_id)')
          .gte('due_date', startDate)
          .lte('due_date', endDate)
          .eq('is_paid', false),
        supabase.from('attendance')
          .select('*')
          .gte('work_date', startDate)
          .lte('work_date', endDate),
        supabase.from('leave_requests')
          .select('*')
          .in('status', ['approved', 'pending'])
          .lte('start_date', endDate)
          .gte('end_date', startDate),
        supabase.from('work_schedules')
          .select('*'),
        supabase.from('salary_slips')
          .select('*')
          .eq('work_month', selectedMonth),
        supabase.from('archived_months')
          .select('work_month')
      ]);

      if (resBrs.data) setBranches(resBrs.data);
      // supabase-js بدون أنواع مولّدة يستنتج العلاقة branches كمصفوفة، وهي فعلياً كائن واحد
      if (resEmps.data) setEmployees(resEmps.data as unknown as Employee[]);
      if (resBds.data) setBonusesAndDeductions(resBds.data);
      if (resLoans.data) setLoanInstallments(resLoans.data);
      if (resAtt.data) setAttendanceLogs(resAtt.data);
      if (resLvs.data) setLeaveRequests(resLvs.data);
      if (resScheds.data) setWorkSchedules(resScheds.data);
      if (resSlips.data) setExistingSlips(resSlips.data);
      if (resArchived.data) {
        setArchivedMonths(resArchived.data.map((r: { work_month: string }) => r.work_month));
      }

    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPayrollData();
  }, [startDate, endDate]);

  const handleAddBonusDeduction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedEmpForBD || bdAmount <= 0) return;
    
    setActionLoading('add_bd');
    try {
      const { data: { user } } = await supabase.auth.getUser();
      
      const { error } = await supabase.from('bonuses_deductions').insert({
        employee_id: selectedEmpForBD.id,
        type: bdType,
        amount: bdAmount,
        reason: bdReason,
        issue_date: new Date().toISOString().split('T')[0], // current date
        created_by: user?.id
      });

      if (error) throw error;

      setShowAddBDModal(false);
      setBdAmount(0);
      setBdReason('');
      
      confetti({ particleCount: 50, spread: 40 });
      toast.success('تم إضافة السجل بنجاح! ✅');
      
      fetchPayrollData();
    } catch {
      toast.error('حدث خطأ أثناء الإضافة');
    } finally {
      setActionLoading(null);
    }
  };

  // قيود المكافآت والخصومات التي تُنشأ مع كشف الراتب (تسويات يدوية + تفاصيل خصومات الحضور)
  const buildSlipAdjustments = (empData: PayrollRow): SlipAdjustment[] => {
    const adjustments: SlipAdjustment[] = [];
    const add = (type: SlipAdjustment['type'], amount: number, reason: string, skipIfExists = false) => {
      if (amount > 0) adjustments.push({ type, amount, reason, issue_date: endDate, skip_if_exists: skipIfExists });
    };

    if (empData.isBonusesOverridden) {
      const diff = empData.totalBonuses - empData.computedBonuses;
      if (diff > 0) add('bonus', diff, `تسوية زيادة مكافآت يدوياً لشهر ${selectedMonth}`);
      else add('deduction', Math.abs(diff), `تسوية تخفيض مكافآت يدوياً لشهر ${selectedMonth}`);
    }

    if (empData.isOtherDeductionsOverridden) {
      const diff = (empData.totalDeductions - empData.totalAttendanceDeductions) - empData.computedOtherDeductions;
      if (diff > 0) add('deduction', diff, `تسوية زيادة خصومات يدوياً لشهر ${selectedMonth}`);
      else add('bonus', Math.abs(diff), `تسوية تخفيض خصومات يدوياً لشهر ${selectedMonth}`);
    }

    if (empData.isAttendanceDeductionsOverridden) {
      add('deduction', empData.totalAttendanceDeductions, `خصم غياب وحضور معدل يدوياً للفترة من ${startDate} إلى ${endDate}`);
    } else if (empData.totalAttendanceDeductions > 0) {
      // تفاصيل خصومات الحضور التلقائية للتدقيق (لا تُكرر إن وُجدت سابقاً)
      add('deduction', empData.absenceDeduction, `خصم غياب غير مبرر (${empData.absencesCount} يوم) للفترة من ${startDate} إلى ${endDate}`, true);
      add('deduction', empData.halfDayDeduction, `خصم نصف يوم (${empData.halfDaysCount} يوم) للفترة من ${startDate} إلى ${endDate}`, true);
      add('deduction', empData.latenessDeduction, `خصم تأخير الحضور (${formatLateDurationArabic(empData.totalLateMinutes)}) للفترة من ${startDate} إلى ${endDate}`, true);
      add('deduction', empData.earlyExitDeduction, `خصم خروج مبكر (${formatLateDurationArabic(empData.totalEarlyExitMinutes)}) للفترة من ${startDate} إلى ${endDate}`, true);
    }

    return adjustments;
  };

  // الكشف + تسديد الأقساط + القيود كلها في transaction واحدة بالسيرفر
  const approveSlip = async (empData: PayrollRow) => {
    const { error } = await supabase.rpc('approve_salary_slip', {
      p_employee_id: empData.id,
      p_work_month: selectedMonth,
      p_basic_salary: empData.basic,
      p_allowances: empData.totalBonuses,
      p_deductions: empData.totalDeductions,
      p_loans_deduction: empData.loanDeduction,
      p_net_salary: empData.netSalary,
      p_installment_ids: empData.loanInstallmentIds ?? [],
      p_adjustments: buildSlipAdjustments(empData),
    });
    if (error) throw error;
  };

  const handleGenerateSlip = async (empData: PayrollRow) => {
    if (existingSlips.some(s => s.employee_id === empData.id && s.work_month === selectedMonth)) {
      toast.error('تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.');
      return;
    }

    setActionLoading(`slip_${empData.id}`);
    try {
      await approveSlip(empData);
      confetti({ particleCount: 100, spread: 60, colors: ['#10B981', '#059669'] });
      toast.success('تم اعتماد راتب الموظف بنجاح! 💸');
      fetchPayrollData();
    } catch (err: unknown) {
      toast.error(`فشل اعتماد الراتب: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleBulkGenerateSlips = async (empsToProcess: PayrollRow[]) => {
    setActionLoading('bulk_generate');
    let successCount = 0;
    const failed: string[] = [];
    try {
      for (const empData of empsToProcess) {
        if (existingSlips.some(s => s.employee_id === empData.id && s.work_month === selectedMonth)) {
          continue;
        }
        try {
          await approveSlip(empData);
          successCount++;
        } catch (err: unknown) {
          console.error(`Error generating slip for ${empData.full_name}:`, err);
          failed.push(empData.full_name);
        }
      }

      if (successCount > 0) {
        confetti({ particleCount: 150, spread: 80, colors: ['#10B981', '#3B82F6'] });
        toast.success(`تم اعتماد رواتب (${successCount}) موظف بنجاح! 💸`);
      }
      if (failed.length > 0) {
        toast.error(`تعذر اعتماد رواتب (${failed.length}) موظف: ${failed.join('، ')}`);
      }
      setShowBulkModal(false);
      fetchPayrollData();
    } finally {
      setActionLoading(null);
    }
  };

  const handleSendBranchNotifications = async () => {
    if (selectedBranch === 'all') {
      toast.error('يرجى اختيار فرع محدد أولاً لإرسال الإشعارات له.');
      return;
    }
    
    setSendingNotifs(true);
    try {
      // 1. جلب الموظفين النشطين في الفرع المختار
      const { data: branchEmps, error: empErr } = await supabase
        .from('employees')
        .select('id, full_name')
        .eq('branch_id', selectedBranch)
        .eq('is_active', true);
        
      if (empErr) throw empErr;
      if (!branchEmps || branchEmps.length === 0) {
        toast.error('لم يتم العثور على موظفين في هذا الفرع.');
        return;
      }

      // 2. جلب كشوف الرواتب المعتمدة لهؤلاء الموظفين للشهر المحدد
      const empIds = branchEmps.map(emp => emp.id);
      const { data: slips, error: slipsErr } = await supabase
        .from('salary_slips')
        .select('employee_id, net_salary')
        .in('employee_id', empIds)
        .eq('work_month', selectedMonth);
        
      if (slipsErr) throw slipsErr;
      if (!slips || slips.length === 0) {
        toast.error('لا توجد كشوف رواتب معتمدة/منشورة لهذا الفرع في الشهر المحدد.');
        return;
      }

      // 3. إدراج الإشعارات دفعة واحدة
      const notifications = slips.map(slip => {
        return {
          employee_id: slip.employee_id,
          title: 'اعتماد ونشر كشف الراتب 💸',
          body: `تم اعتماد وصرف كشف راتبك لشهر (${selectedMonth}) بصافي مستلم قدره (${slip.net_salary.toLocaleString()} د.ع). يمكنك الاطلاع عليه من التطبيق.`,
          type: 'salary',
          is_read: false
        };
      });

      const { error: notifErr } = await supabase.from('notifications').insert(notifications);
      if (notifErr) throw notifErr;

      confetti({ particleCount: 80, spread: 50, colors: ['#3B82F6', '#60A5FA'] });
      toast.success(`تم إرسال إشعارات كشوف الرواتب بنجاح لـ (${slips.length}) موظف في الفرع! 🔔`);
    } catch (err: unknown) {
      toast.error(`فشل إرسال إشعارات الفرع: ${errorMessage(err)}`);
    } finally {
      setSendingNotifs(false);
    }
  };

  const handleRevertSlip = async (empData: PayrollRow) => {
    if (archivedMonths.includes(selectedMonth)) {
      toast.error('هذا الشهر مؤرشف مالياً ومقفل تماماً 🔒');
      return;
    }

    // Check if the slip exists in existingSlips
    const slip = existingSlips.find(s => s.employee_id === empData.id);
    if (!slip) return;

    setActionLoading(`revert_${empData.id}`);
    try {
      // يحذف الكشف ويُرجع نفس الأقساط والقيود التي أنشأها (transaction واحدة)
      const { error } = await supabase.rpc('revert_salary_slip', {
        p_slip_id: slip.id,
        p_period_start: startDate,
        p_period_end: endDate,
      });
      if (error) throw error;

      toast.success('تم التراجع عن اعتماد الراتب بنجاح! 🔄');
      fetchPayrollData();
    } catch (err: unknown) {
      toast.error(`فشل في التراجع عن الاعتماد: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleArchiveMonth = async () => {
    const confirmArchive = window.confirm(
      `⚠️ تحذير أمني: هل أنت متأكد من أرشفة كشوف الرواتب لشهر (${selectedMonth})؟\n\n` +
      `عند الأرشفة:\n` +
      `- سيتم حذف سجلات الحضور والغياب التفصيلية لهذا الشهر بشكل نهائي لتوفير المساحة.\n` +
      `- سيتم حذف سجلات المكافآت والخصومات التفصيلية (حيث تم حفظ المبالغ الصافية نهائياً في كشوف الرواتب).\n` +
      `- سيتم قفل الشهر مالياً ولن تتمكن من تعديل أو التراجع عن أي راتب بعد الآن.\n` +
      `- لا يمكن التراجع عن هذه العملية لاحقاً.\n\n` +
      `هل تريد المتابعة؟`
    );

    if (!confirmArchive) return;

    setActionLoading('archive_month');
    try {
      const { data, error } = await supabase.rpc('safe_archive_payroll_month', {
        target_month: selectedMonth,
        cycle_start_day: cycleStartDay,
        cycle_end_day: cycleEndDay
      });

      if (error) throw error;

      if (data && data.success === false) {
        let errorMsg = data.error;
        if (data.missing_employees && data.missing_employees.length > 0) {
          errorMsg += `\n\nالموظفون الذين لم يتم اعتماد رواتبهم بعد:\n- ` + data.missing_employees.join('\n- ');
        }
        alert(errorMsg);
        toast.error(data.error || 'فشلت عملية الأرشفة');
      } else {
        toast.success(data.message || 'تمت أرشفة الشهر بنجاح! 📦');
        confetti({ particleCount: 100, spread: 70, origin: { y: 0.6 } });
        fetchPayrollData();
      }
    } catch (err: unknown) {
      console.error(err);
      toast.error(`خطأ أثناء الأرشفة: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const toggleExcuseDay = (employeeId: string, dateStr: string) => {
    setExcusedDays(prev => {
      const currentList = prev[employeeId] || [];
      const updatedList = currentList.includes(dateStr)
        ? currentList.filter(d => d !== dateStr)
        : [...currentList, dateStr];
      
      return {
        ...prev,
        [employeeId]: updatedList
      };
    });
  };

  // Filter out employees who joined AFTER the end of this payroll cycle
  const validEmployees = employees.filter(emp => {
    const effectiveJoinDate = emp.join_date || emp.created_at;
    if (!effectiveJoinDate) return true;
    const createdDate = new Date(effectiveJoinDate).getTime();
    const cycleEnd = new Date(endDate + 'T23:59:59.999Z').getTime();
    return createdDate <= cycleEnd;
  });

  // Compile processed payroll data with smart attendance & absence calculation
  const processedPayroll = validEmployees.map(emp => {
    let nominalBasic = emp.monthly_salary_iqd || 0;
    
    if (emp.future_salary_iqd && emp.future_salary_month) {
      const futureMonthStr = emp.future_salary_month.substring(0, 7);
      if (selectedMonth >= futureMonthStr) {
        nominalBasic = emp.future_salary_iqd;
      }
    }

    let basic = nominalBasic;
    const start = new Date(startDate);
    const end = new Date(endDate);

    // Prorate salary if the employee joined mid-cycle
    const effectiveJoinDateStr = emp.join_date;
    if (effectiveJoinDateStr) {
      const joinDate = new Date(effectiveJoinDateStr);
      const joinDay = new Date(joinDate.getFullYear(), joinDate.getMonth(), joinDate.getDate());
      const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
      
      if (joinDay > startDay) {
        const totalCycleDays = Math.round((end.getTime() - startDay.getTime()) / (1000 * 3600 * 24)) + 1;
        const daysWorkedInCycle = Math.round((end.getTime() - joinDay.getTime()) / (1000 * 3600 * 24)) + 1;
        
        if (daysWorkedInCycle > 0 && daysWorkedInCycle < totalCycleDays) {
          basic = Math.round((nominalBasic / totalCycleDays) * daysWorkedInCycle);
        }
      }
    }
    
    // Dynamic Attendance Calculations
    
    // Define the limit day (if selectedRange is current month, calculate up to today)
    const today = new Date();
    const todayNormalized = new Date(today.getFullYear(), today.getMonth(), today.getDate());

    // Get work schedules for the employee (employee-specific -> department -> default)
    // Default working schedule in Iraq is Saturday(6) to Thursday(4)
    const empSched = resolveWorkSchedule(emp, workSchedules);
    const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];

    let presentsCount = 0;
    let latesCount = 0;
    let totalLateMinutes = 0;
    let earlyExitsCount = 0;
    let totalEarlyExitMinutes = 0;
    let halfDaysCount = 0;
    let absencesCount = 0;
    let paidLeavesCount = 0;
    let scheduledWorkDays = 0;
    let unconfirmedAbsencesCount = 0;

    const detailLogs: DetailLog[] = [];
    const empExcuses = excusedDays[emp.id] || [];

    let joinDay: Date | null = null;
    if (emp.created_at) {
      const jd = new Date(emp.created_at);
      joinDay = new Date(jd.getFullYear(), jd.getMonth(), jd.getDate());
    }

    const loopDate = new Date(start);
    while (loopDate <= end) {
      const year = loopDate.getFullYear();
      const month = loopDate.getMonth() + 1;
      const day = loopDate.getDate();
      const dateStr = `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
      
      const weekday = loopDate.getDay(); // JS getDay: 0 is Sunday, 1 is Monday... 6 is Saturday
      const isWorkingDay = workDays.includes(weekday);
      
      if (isWorkingDay) {
        const isBeforeJoining = joinDay && loopDate < joinDay;

        if (isBeforeJoining) {
          detailLogs.push({
            date: dateStr,
            status: 'قبل التعيين 🕒',
            time: '-',
            note: 'هذا اليوم يسبق تاريخ مباشرة الموظف للعمل',
            isAbsenceDay: false
          });
        } else {
          const isPastOrToday = loopDate <= todayNormalized;
          if (isPastOrToday) {
            scheduledWorkDays++;
          }

          const isExcused = empExcuses.includes(dateStr);
          
          // Check attendance records
          const attRecord = attendanceLogs.find(log => log.employee_id === emp.id && log.work_date === dateStr);
          
          // Check approved leaves
          const isDateWithinRange = (date: Date, startStr: string, endStr: string) => {
            const d = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
            const s = new Date(new Date(startStr).getFullYear(), new Date(startStr).getMonth(), new Date(startStr).getDate()).getTime();
            const e = new Date(new Date(endStr).getFullYear(), new Date(endStr).getMonth(), new Date(endStr).getDate()).getTime();
            return d >= s && d <= e;
          };
          
          const leaveRecord = leaveRequests.find(l => l.employee_id === emp.id && l.status === 'approved' && isDateWithinRange(loopDate, l.start_date, l.end_date));

          if (attRecord) {
            const status = attRecord.status;
            const isApplied = attRecord.deduction_status === 'applied';
            const isIgnored = attRecord.deduction_status === 'ignored';

            let earlyExitMins = 0;
            if (attRecord.check_out_time) {
              const schedCheckOut = empSched ? empSched.check_out_time : '17:00:00';
              const schedOutMins = parseScheduleMinutes(schedCheckOut);
              const actualOutMins = getBaghdadMinutesFromIso(attRecord.check_out_time);
              const diffEarly = schedOutMins - actualOutMins;
              if (diffEarly > 0) {
                earlyExitMins = diffEarly;
              }
            }

            if (isPastOrToday) {
              if (status === 'present') presentsCount++;
              else if (status === 'late') {
                presentsCount++;
                if (isApplied) {
                  latesCount++;
                  // Calculate late minutes
                  const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
                  const schedInMins = parseScheduleMinutes(schedCheckIn);
                  const actualInMins = attRecord.check_in_time ? getBaghdadMinutesFromIso(attRecord.check_in_time) : schedInMins;
                  const diffLate = actualInMins - schedInMins;
                  const lateMins = diffLate > 0 ? diffLate : 0;
                  totalLateMinutes += lateMins;
                }
              }
              else if (status === 'half_day') halfDaysCount++;
              else if (status === 'absent') {
                if (isApplied) absencesCount++;
              }

              // Early exit check
              if (earlyExitMins > 0 && isApplied) {
                earlyExitsCount++;
                totalEarlyExitMinutes += earlyExitMins;
              }
            }
            
            let statusAr = 'حاضر ✅';
            const noteParts = [];
            if (status === 'late') {
              statusAr = isApplied ? 'متأخر (تم تطبيق الخصم) ⚠️' : (isIgnored ? 'متأخر (تم تجاهل الخصم) 🟢' : 'متأخر (معلق) ⏳');
              // Calculate late minutes for display
              const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
              const schedInMins = parseScheduleMinutes(schedCheckIn);
              const actualInMins = attRecord.check_in_time ? getBaghdadMinutesFromIso(attRecord.check_in_time) : schedInMins;
              const diffLate = actualInMins - schedInMins;
              const lateMins = diffLate > 0 ? diffLate : 0;
              noteParts.push(`تأخير: ${formatLateDurationArabic(lateMins)}`);
            } else if (status === 'half_day') {
              statusAr = 'نصف يوم 🌓';
              noteParts.push('دوام غير مكتمل');
            } else if (status === 'absent') {
              statusAr = isApplied ? 'غياب (تم تطبيق الخصم) ❌' : 'غياب (تم تجاهل الخصم) 🟢';
              noteParts.push(attRecord.deduction_reason || 'غياب غير مبرر');
            }

            if (earlyExitMins > 0) {
              noteParts.push(`خروج مبكر: ${formatLateDurationArabic(earlyExitMins)}`);
              if (status === 'present') {
                statusAr = isApplied ? 'خروج مبكر (خصم) ⚠️' : 'خروج مبكر (تجاهل الخصم) 🟢';
              }
            }

            const noteAr = noteParts.length > 0 ? noteParts.join(' | ') : 'بصمة دوام اعتيادية';

            detailLogs.push({
              date: dateStr,
              status: statusAr,
              time: attRecord.check_in_time ? new Date(attRecord.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
              note: noteAr,
              isAbsenceDay: false
            });
          } else if (leaveRecord) {
            if (isPastOrToday) {
              if (leaveRecord.is_paid) {
                paidLeavesCount++;
              } else {
                absencesCount++;
              }
            }
            detailLogs.push({
              date: dateStr,
              status: leaveRecord.is_paid ? 'إجازة معتمدة 🌴' : 'إجازة بدون راتب ❌',
              time: '-',
              note: leaveRecord.reason ? `سبب الإجازة: ${leaveRecord.reason}` : 'إجازة إدارية معتمدة',
              isAbsenceDay: false
            });
          } else {
            // No attendance record and no leave
            const isPast = loopDate < todayNormalized || (loopDate.getTime() === todayNormalized.getTime() && today.getHours() >= 17);
            if (isPast) {
              if (isExcused) {
                if (isPastOrToday) {
                  presentsCount++; // Treated as present (excused)
                }
                detailLogs.push({
                  date: dateStr,
                  status: 'معفى (عذر إداري) 🟢',
                  time: '-',
                  note: 'غياب تم إعفاؤه إدارياً بواسطة المدير المباشر',
                  isAbsenceDay: true,
                  isExcused: true
                });
              } else {
                // Not excused, no attendance, no leave -> Unconfirmed absence (no auto-deduction)
                if (isPastOrToday) {
                  unconfirmedAbsencesCount++;
                }
                detailLogs.push({
                  date: dateStr,
                  status: 'يوم بدون حضور ⚠️',
                  time: '-',
                  note: 'لم يتم تسجيل حضور، ولم يتم تطبيق خصم غياب من قبل الإدارة بعد',
                  isAbsenceDay: false,
                  isExcused: false
                });
              }
            } else {
              detailLogs.push({
                date: dateStr,
                status: 'لم يحن بعد ⏳',
                time: '-',
                note: loopDate.getTime() === todayNormalized.getTime() ? 'قيد الانتظار لموعد الدوام اليوم' : 'يوم عمل مجدول مستقبلي',
                isAbsenceDay: false
              });
            }
          }
        }
      }

      // Advance loopDate by 1 day
      loopDate.setDate(loopDate.getDate() + 1);
    }

    // Salary deductions calculation
    let workdayMinutes = 480; // Default fallback: 8 hours (480 mins)
    if (empSched && empSched.check_in_time && empSched.check_out_time) {
      const [inH, inM] = empSched.check_in_time.split(':').map(Number);
      const [outH, outM] = empSched.check_out_time.split(':').map(Number);
      const inMinutes = inH * 60 + inM;
      const outMinutes = outH * 60 + outM;
      if (outMinutes > inMinutes) {
        workdayMinutes = outMinutes - inMinutes;
      }
    }

    // Use nominalBasic for daily wage calculations, so mid-month joiners aren't under-penalized
    const dailyWage = nominalBasic / 30;
    const absenceDeduction = Math.round(absencesCount * dailyWage);
    const halfDayDeduction = Math.round(halfDaysCount * dailyWage * 0.5);
    const latenessDeduction = Math.round(totalLateMinutes * (dailyWage / workdayMinutes));
    const earlyExitDeduction = Math.round(totalEarlyExitMinutes * (dailyWage / workdayMinutes));

    // Apply overrides
    const empOverrides = payrollOverrides[emp.id] || {};

    const computedAttendanceDeductions = absenceDeduction + halfDayDeduction + latenessDeduction + earlyExitDeduction;
    const finalAttendanceDeductions = empOverrides.attendanceDeductions !== undefined 
      ? empOverrides.attendanceDeductions 
      : computedAttendanceDeductions;

    const empBDs = bonusesAndDeductions.filter(bd => bd.employee_id === emp.id);
    
    const computedBonuses = empBDs.filter(bd => bd.type === 'bonus').reduce((sum, bd) => sum + Number(bd.amount), 0);
    const finalBonuses = empOverrides.bonuses !== undefined 
      ? empOverrides.bonuses 
      : computedBonuses;

    const computedOtherDeductions = empBDs.filter(bd => bd.type === 'deduction').reduce((sum, bd) => sum + Number(bd.amount), 0);
    const finalOtherDeductions = empOverrides.otherDeductions !== undefined 
      ? empOverrides.otherDeductions 
      : computedOtherDeductions;

    const finalDeductions = finalOtherDeductions + finalAttendanceDeductions;
    
    const empLoans = loanInstallments.filter(l => l.loans?.employee_id === emp.id);
    const loanDeduction = empLoans.reduce((sum, l) => sum + Number(l.amount), 0);
    const loanInstallmentIds = empLoans.map(l => l.id);

    const netSalary = basic + finalBonuses - finalDeductions - loanDeduction;
    const isIssued = existingSlips.some(slip => slip.employee_id === emp.id);

    let displayBasic = basic;
    let displayBonuses = finalBonuses;
    let displayAttendanceDeductions = finalAttendanceDeductions;
    let displayDeductions = finalDeductions;
    let displayLoanDeduction = loanDeduction;
    let displayNetSalary = netSalary;

    const issuedSlip = existingSlips.find(slip => slip.employee_id === emp.id);
    if (issuedSlip) {
      displayBasic = Number(issuedSlip.basic_salary);
      displayBonuses = Number(issuedSlip.allowances);
      displayLoanDeduction = Number(issuedSlip.loans_deduction);
      displayDeductions = Number(issuedSlip.deductions);
      displayNetSalary = Number(issuedSlip.net_salary);
      displayAttendanceDeductions = Math.min(displayDeductions, finalAttendanceDeductions);
    }

    return {
      ...emp,
      basic: displayBasic,
      scheduledWorkDays,
      presentsCount,
      latesCount,
      totalLateMinutes,
      latenessDeduction,
      earlyExitsCount,
      totalEarlyExitMinutes,
      earlyExitDeduction,
      halfDaysCount,
      absencesCount,
      paidLeavesCount,
      absenceDeduction,
      halfDayDeduction,
      totalAttendanceDeductions: displayAttendanceDeductions,
      totalBonuses: displayBonuses,
      totalDeductions: displayDeductions,
      loanDeduction: displayLoanDeduction,
      loanInstallmentIds,
      netSalary: displayNetSalary,
      isIssued,
      detailLogs,
      bonusesList: empBDs.filter(bd => bd.type === 'bonus'),
      otherDeductionsList: empBDs.filter(bd => bd.type === 'deduction'),
      loanInstallmentsList: empLoans,
      
      // Smart Validation Flags
      isNetNegative: !isIssued && displayNetSalary < 0,
      isAttendanceMissing: !isIssued && scheduledWorkDays > 0 && presentsCount === 0 && absencesCount === 0 && halfDaysCount === 0 && paidLeavesCount === 0,
      hasPendingLeave: !isIssued && leaveRequests.some(l => l.employee_id === emp.id && l.status === 'pending'),
      unconfirmedAbsencesCount: isIssued ? 0 : unconfirmedAbsencesCount,

      // Overridden flags for styling and database adjustments
      isBonusesOverridden: empOverrides.bonuses !== undefined,
      isAttendanceDeductionsOverridden: empOverrides.attendanceDeductions !== undefined,
      isOtherDeductionsOverridden: empOverrides.otherDeductions !== undefined,
      computedAttendanceDeductions,
      computedBonuses,
      computedOtherDeductions
    };
  });

  const filteredPayroll = processedPayroll.filter(emp => {
    const matchesSearch = (emp.full_name || '').toLowerCase().includes(searchTerm.toLowerCase());
    const matchesBranch = selectedBranch === 'all' || emp.branch_id === selectedBranch;
    return matchesSearch && matchesBranch;
  });

  const totalNetSalaries = filteredPayroll.reduce((sum, emp) => sum + emp.netSalary, 0);
  const totalBasicSalaries = filteredPayroll.reduce((sum, emp) => sum + emp.basic, 0);
  const totalBonuses = filteredPayroll.reduce((sum, emp) => sum + emp.totalBonuses, 0);
  const totalAttendanceDeductions = filteredPayroll.reduce((sum, emp) => sum + emp.totalAttendanceDeductions, 0);
  const totalOtherDeductions = filteredPayroll.reduce((sum, emp) => sum + (emp.totalDeductions - emp.totalAttendanceDeductions), 0);
  const totalLoans = filteredPayroll.reduce((sum, emp) => sum + emp.loanDeduction, 0);

  const arabicMonths: Record<string, string> = {
    '01': 'كانون الثاني (يناير)',
    '02': 'شباط (فبراير)',
    '03': 'آذار (مارس)',
    '04': 'نيسان (أبريل)',
    '05': 'أيار (مايو)',
    '06': 'حزيران (يونيو)',
    '07': 'تموز (يوليو)',
    '08': 'آب (أغسطس)',
    '09': 'أيلول (سبتمبر)',
    '10': 'تشرين الأول (أكتوبر)',
    '11': 'تشرين الثاني (نوفمبر)',
    '12': 'كانون الأول (ديسمبر)',
  };

  // Branch bulk calculation helpers
  const selectedBranchObj = branches.find(b => b.id === selectedBranch);
  const branchName = selectedBranchObj ? selectedBranchObj.name : '';
  const pendingBranchEmps = filteredPayroll.filter(emp => !emp.isIssued);
  const totalBranchNet = pendingBranchEmps.reduce((sum, emp) => sum + emp.netSalary, 0);
  const totalBranchBase = pendingBranchEmps.reduce((sum, emp) => sum + emp.basic, 0);
  const totalBranchBonuses = pendingBranchEmps.reduce((sum, emp) => sum + emp.totalBonuses, 0);
  const totalBranchDeductions = pendingBranchEmps.reduce((sum, emp) => sum + emp.totalDeductions, 0);
  const totalBranchLoans = pendingBranchEmps.reduce((sum, emp) => sum + emp.loanDeduction, 0);

  // Retrieve the selected employee for breakdown dynamically from the processed list
  const selectedEmpForBreakdown = processedPayroll.find(emp => emp.id === selectedEmpIdForBreakdown);

  const monthParts = selectedMonth ? selectedMonth.split('-') : [];
  const currentYearVal = monthParts[0] || new Date().getFullYear().toString();
  const currentMonthVal = monthParts[1] || (new Date().getMonth() + 1).toString().padStart(2, '0');
  const currentMonthName = arabicMonths[currentMonthVal] || currentMonthVal;
  const isMonthArchived = archivedMonths.includes(selectedMonth);

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      {/* Print-Only Header Block */}
      <div className="hidden print:block text-slate-900 text-right p-6 border-b-2 border-slate-900 mb-8 font-sans" dir="rtl">
        <div className="flex justify-between items-start mb-6">
          <div>
            <h1 className="text-2xl font-black mb-1">قسم ادارة موظفين شركة بترى</h1>
            <p className="text-xs text-slate-500 font-bold">كشف رواتب الموظفين التفصيلي الشهري</p>
          </div>
          <div className="text-left font-mono text-[10px]">
            <p>تاريخ الطباعة: {new Date().toLocaleDateString('ar-IQ')}</p>
            <p>الوقت: {new Date().toLocaleTimeString('ar-IQ')}</p>
          </div>
        </div>
        
        <div className="grid grid-cols-3 gap-4 bg-slate-50 p-4 rounded-2xl border border-slate-200 text-xs mb-4">
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الشهر والسنة:</span>
            <span className="font-black text-sm text-slate-800">
              {currentMonthName} - {currentYearVal}
            </span>
          </div>
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الفترة المالية المحتسبة:</span>
            <span className="font-black text-sm text-slate-800 font-mono">
              {startDate} إلى {endDate}
            </span>
          </div>
          <div>
            <span className="font-bold text-slate-500 block mb-0.5">الفرع المالي:</span>
            <span className="font-black text-sm text-slate-800">
              {selectedBranch === 'all' ? 'كافة فروع الشركة' : branches.find(b => b.id === selectedBranch)?.name || '-'}
            </span>
          </div>
        </div>
      </div>

      {/* Header & Stats */}
      <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col lg:flex-row items-start lg:items-center justify-between gap-6 print:hidden">
        <div>
          <h3 className="text-xl font-extrabold text-white flex items-center gap-2 mb-2">
            <Banknote className="w-6 h-6 text-teal-400" />
            <span>نظام الرواتب والدوام الذكي (Payroll Hub)</span>
            {isMonthArchived && (
              <span className="flex items-center gap-1.5 px-3 py-1 bg-purple-500/20 border border-purple-500/40 text-purple-300 rounded-full font-bold text-xs select-none">
                <Archive className="w-3.5 h-3.5" />
                <span>مؤرشف ومغلق مالياً 📦</span>
              </span>
            )}
          </h3>
          <p className="text-xs text-slate-400">احتساب فوري للأجور والخصومات التلقائية للغيابات وأنصاف الأيام بناءً على البصمة الجغرافية</p>
        </div>

        <div className="flex flex-wrap items-center gap-3 bg-slate-950/50 p-2 rounded-2xl border border-slate-800/50">
          {/* Select Month Dropdown */}
          <div className="flex flex-col gap-1 px-2">
            <span className="text-[9px] text-slate-400 font-bold">الشهر</span>
            <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 hover:border-teal-500/50 transition-colors">
              <CalendarIcon className="w-3.5 h-3.5 text-teal-400" />
              <select
                value={currentMonthVal}
                onChange={(e) => {
                  const newMonth = e.target.value;
                  handleMonthChange(`${currentYearVal}-${newMonth}`);
                }}
                className="bg-transparent border-none text-white text-[11px] outline-none cursor-pointer font-bold select-none pr-1 focus:ring-0"
              >
                <option value="01" className="bg-slate-900 text-white">1 - كانون الثاني (يناير)</option>
                <option value="02" className="bg-slate-900 text-white">2 - شباط (فبراير)</option>
                <option value="03" className="bg-slate-900 text-white">3 - آذار (مارس)</option>
                <option value="04" className="bg-slate-900 text-white">4 - نيسان (أبريل)</option>
                <option value="05" className="bg-slate-900 text-white">5 - أيار (مايو)</option>
                <option value="06" className="bg-slate-900 text-white">6 - حزيران (يونيو)</option>
                <option value="07" className="bg-slate-900 text-white">7 - تموز (يوليو)</option>
                <option value="08" className="bg-slate-900 text-white">8 - آب (أغسطس)</option>
                <option value="09" className="bg-slate-900 text-white">9 - أيلول (سبتمبر)</option>
                <option value="10" className="bg-slate-900 text-white">10 - تشرين الأول (أكتوبر)</option>
                <option value="11" className="bg-slate-900 text-white">11 - تشرين الثاني (نوفمبر)</option>
                <option value="12" className="bg-slate-900 text-white">12 - كانون الأول (ديسمبر)</option>
              </select>
            </div>
          </div>

          {/* Select Year Dropdown */}
          <div className="flex flex-col gap-1 px-2 border-r border-slate-800/80">
            <span className="text-[9px] text-slate-400 font-bold">السنة</span>
            <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 hover:border-teal-500/50 transition-colors">
              <CalendarIcon className="w-3.5 h-3.5 text-teal-400" />
              <select
                value={currentYearVal}
                onChange={(e) => {
                  const newYear = e.target.value;
                  handleMonthChange(`${newYear}-${currentMonthVal}`);
                }}
                className="bg-transparent border-none text-white text-[11px] outline-none cursor-pointer font-bold select-none focus:ring-0"
              >
                {Array.from({ length: 9 }, (_, i) => 2024 + i).map(year => (
                  <option key={year} value={year.toString()} className="bg-slate-900 text-white">
                    {year}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Calculated Date Range (Read-Only Info Badge) */}
          <div className="flex flex-col gap-1 px-3 border-r border-slate-800/80 justify-center">
            <span className="text-[9px] text-slate-400 font-bold">الفترة المالية المحتسبة تلقائياً</span>
            <div className="text-[11px] text-teal-300 font-extrabold font-mono bg-teal-950/20 border border-teal-500/15 px-3 py-1.5 rounded-xl flex items-center gap-1.5 select-none">
              <Clock className="w-3 h-3 text-teal-400" />
              <span>{startDate}</span>
              <span className="text-slate-500">←</span>
              <span>{endDate}</span>
            </div>
          </div>

          <div className="flex flex-col items-end px-4 py-1 border-r border-slate-800/80">
            <span className="text-[9px] text-slate-400 font-bold">صافي تكلفة الرواتب المرصودة</span>
            <span className="text-md font-black text-emerald-400">{totalNetSalaries.toLocaleString()} <span className="text-[10px] font-bold text-slate-400">د.ع</span></span>
          </div>
        </div>
      </div>

      {/* Main Table Area */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl print:border-none print:bg-transparent print:p-0 print:shadow-none">
        <div className="flex flex-col md:flex-row justify-between gap-4 mb-6 print:hidden">
          <div className="flex items-center gap-3 print:hidden">
            <div className="relative">
              <input
                type="text"
                placeholder="ابحث باسم الموظف..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full sm:w-64 bg-slate-950/80 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-2 px-4 pr-10 text-xs text-white placeholder-slate-500 outline-none transition-all"
              />
              <Search className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
            </div>
            
            <div className="flex items-center gap-2 bg-slate-950/80 border border-slate-800 rounded-2xl px-3 py-2">
              <Building className="w-4 h-4 text-teal-400" />
              <select 
                value={selectedBranch}
                onChange={(e) => setSelectedBranch(e.target.value)}
                className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
              >
                <option value="all" className="bg-slate-900">جميع الفروع</option>
                {branches.map(b => (
                  <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
                ))}
              </select>
            </div>
          </div>
          
          <div className="flex items-center gap-3 print:hidden">
            {!isMonthArchived && selectedBranch !== 'all' && (
              <>
                <button
                  onClick={() => setShowBulkModal(true)}
                  className="flex items-center justify-center gap-2 py-2 px-4 bg-teal-650 hover:bg-teal-600 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
                >
                  <CheckCircle className="w-4 h-4" />
                  <span>اعتماد رواتب الفرع لشهر {selectedMonth}</span>
                </button>
                <button
                  onClick={handleSendBranchNotifications}
                  disabled={sendingNotifs}
                  className="flex items-center justify-center gap-2 py-2 px-4 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-800 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
                >
                  {sendingNotifs ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Bell className="w-4 h-4" />
                  )}
                  <span>إرسال إشعار للفرع</span>
                </button>
              </>
            )}

            <button 
              onClick={() => window.print()}
              className="flex items-center justify-center gap-2 py-2 px-4 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer"
            >
              <Printer className="w-4 h-4" />
              <span>طباعة مسودة كشف الرواتب</span>
            </button>

            {isMonthArchived ? (
              <div className="flex items-center gap-1.5 px-3 py-2 bg-purple-500/10 border border-purple-500/20 text-purple-400 rounded-2xl font-bold text-xs select-none">
                <Archive className="w-4 h-4" />
                <span>مؤرشف ومغلق مالياً 📦</span>
              </div>
            ) : (
              <button 
                onClick={handleArchiveMonth}
                disabled={actionLoading === 'archive_month'}
                className="flex items-center justify-center gap-2 py-2 px-4 bg-purple-650 hover:bg-purple-600 disabled:bg-purple-800 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
                title="أرشفة وحذف سجلات الدوام التفصيلية لهذا الشهر بشكل نهائي"
              >
                {actionLoading === 'archive_month' ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Archive className="w-4 h-4" />
                )}
                <span>أرشفة وإغلاق الشهر 📦</span>
              </button>
            )}
          </div>
        </div>

        <div className="overflow-x-auto rounded-2xl border border-slate-800/60 print:border-none print:shadow-none">
          <table className="w-full text-right border-collapse">
            <thead>
              <tr className="bg-slate-950/80 text-slate-300 text-xs font-bold border-b border-slate-800/80">
                <th className="p-4">اسم الموظف</th>
                <th className="p-4">الفرع</th>
                <th className="p-4 text-slate-200">الراتب الأساسي</th>
                <th className="p-4 text-emerald-400">مكافآت (+)</th>
                <th className="p-4 text-amber-500">خصم غيابات الدوام (-)</th>
                <th className="p-4 text-rose-400">خصومات أخرى (-)</th>
                <th className="p-4 text-orange-400">السلف (-)</th>
                <th className="p-4 text-teal-300 text-lg">الراتب الصافي (Net)</th>
                <th className="p-4 text-left print:hidden">الإجراءات</th>
              </tr>
            </thead>
            <tbody>
              {filteredPayroll.length === 0 ? (
                <tr>
                  <td colSpan={9} className="p-8 text-center text-slate-500 text-xs">
                    لا توجد بيانات موظفين مطابقة للشروط
                  </td>
                </tr>
              ) : (
                filteredPayroll.map(emp => (
                  <tr key={emp.id} className="border-b border-slate-800/40 hover:bg-slate-900/30 text-xs transition-colors">
                    <td className="p-4">
                      <div className="flex flex-col">
                        <span className="font-bold text-white text-xs">{emp.full_name}</span>
                        
                        {/* Smart Validation Badges */}
                        <div className="flex flex-wrap gap-1 mt-1 justify-start print:hidden">
                          {emp.isNetNegative && (
                            <span className="px-2 py-0.5 bg-rose-500/15 border border-rose-500/30 text-rose-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                              <span>الراتب الصافي سالب</span>
                              <span>⚠️</span>
                            </span>
                          )}
                          {emp.isAttendanceMissing && (
                            <span className="px-2 py-0.5 bg-amber-500/15 border border-amber-500/30 text-amber-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                              <span>لا توجد بصمات حضور</span>
                              <span>⚠️</span>
                            </span>
                          )}
                          {emp.hasPendingLeave && (
                            <span className="px-2 py-0.5 bg-sky-500/15 border border-sky-500/30 text-sky-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                              <span>طلب إجازة معلق</span>
                              <span>⏳</span>
                            </span>
                          )}
                          {emp.unconfirmedAbsencesCount > 0 && (
                            <span className="px-2 py-0.5 bg-orange-500/15 border border-orange-500/30 text-orange-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                              <span>غياب غير مثبت ({emp.unconfirmedAbsencesCount} أيام)</span>
                              <span>⚠️</span>
                            </span>
                          )}
                        </div>
                        {isMonthArchived ? (
                          <span className="text-[10px] text-slate-500 font-bold mt-1 text-right select-none block">
                            📦 تم أرشفة وحذف السجلات التفصيلية
                          </span>
                        ) : (
                          <button 
                            onClick={() => setSelectedEmpIdForBreakdown(emp.id)}
                            className="text-[10px] text-teal-400 hover:text-teal-300 font-bold mt-1 text-right flex items-center gap-1 cursor-pointer print:hidden"
                          >
                            <Info className="w-3.5 h-3.5" />
                            <span>عرض تفاصيل الحضور والخصومات</span>
                          </button>
                        )}
                      </div>
                    </td>
                    <td className="p-4 text-slate-400 font-bold">{emp.branches?.name || '-'}</td>
                    <td className="p-4 font-bold text-slate-200">{emp.basic.toLocaleString()} د.ع</td>
                    <td className="p-4 font-bold text-emerald-400">
                      {renderEditableCell(emp, 'bonuses', emp.totalBonuses, 'text-emerald-400', '+ ')}
                    </td>
                    <td className="p-4 font-bold text-amber-500">
                      {renderEditableCell(emp, 'attendanceDeductions', emp.totalAttendanceDeductions, 'text-amber-500', '- ')}
                      {!emp.isAttendanceDeductionsOverridden && emp.totalAttendanceDeductions > 0 && (
                        <span className="block text-[9px] opacity-75 text-right mt-1">
                          ({emp.absencesCount} غياب ، {emp.halfDaysCount} نصف يوم)
                        </span>
                      )}
                    </td>
                    <td className="p-4 font-bold text-rose-400">
                      {renderEditableCell(emp, 'otherDeductions', (emp.totalDeductions - emp.totalAttendanceDeductions), 'text-rose-400', '- ')}
                    </td>
                    <td className="p-4 font-bold text-orange-400">
                      {emp.loanDeduction > 0 ? `- ${emp.loanDeduction.toLocaleString()} د.ع` : '-'}
                    </td>
                    <td className="p-4 font-black text-teal-300 text-sm bg-teal-900/10">
                      {emp.netSalary.toLocaleString()} د.ع
                    </td>
                    <td className="p-4 text-left print:hidden">
                      <div className="flex items-center justify-end gap-2">
                        {!isMonthArchived && (
                          <button
                            onClick={() => {
                              setSelectedEmpForBD(emp);
                              setShowAddBDModal(true);
                            }}
                            className="p-2 bg-slate-800 border border-slate-700 text-slate-300 hover:text-white hover:bg-slate-700 rounded-xl transition-all cursor-pointer"
                            title="إضافة تسوية مالية (مكافأة أو خصم)"
                          >
                            <Plus className="w-4 h-4" />
                          </button>
                        )}
                        
                        {emp.isIssued ? (
                          <div className="flex items-center gap-2">
                            <span className="flex items-center gap-1.5 px-3 py-2 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 rounded-xl font-bold text-[10px]">
                              <CheckCircle className="w-3.5 h-3.5" />
                              <span>تم الاعتماد</span>
                            </span>
                            {!isMonthArchived && (
                              <button
                                disabled={actionLoading === `revert_${emp.id}`}
                                onClick={() => {
                                  if(window.confirm('هل أنت متأكد من رغبتك في إلغاء اعتماد هذا الراتب؟ سيتم مسح قيود الخصم الأوتوماتيكية وإرجاع السلف إلى حالة غير مدفوعة.')) {
                                    handleRevertSlip(emp);
                                  }
                                }}
                                className="p-2 bg-rose-500/10 border border-rose-500/20 text-rose-400 hover:bg-rose-500 hover:text-white rounded-xl transition-all cursor-pointer"
                                title="إلغاء الاعتماد والتعديل"
                              >
                                {actionLoading === `revert_${emp.id}` ? (
                                  <Loader2 className="w-4 h-4 animate-spin" />
                                ) : (
                                  <X className="w-4 h-4" />
                                )}
                              </button>
                            )}
                          </div>
                        ) : (
                          !isMonthArchived && (
                            <button
                              disabled={actionLoading === `slip_${emp.id}`}
                              onClick={() => handleGenerateSlip(emp)}
                              className="flex items-center gap-1.5 px-3 py-2 bg-teal-650/20 hover:bg-teal-600/40 border border-teal-500/30 text-teal-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                            >
                              {actionLoading === `slip_${emp.id}` ? (
                                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                              ) : (
                                <>
                                  <CheckCircle className="w-3.5 h-3.5" />
                                  <span>اعتماد الراتب</span>
                                </>
                              )}
                            </button>
                          )
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            <tfoot>
              <tr className="bg-slate-950 font-bold border-t border-slate-800 text-xs print:bg-slate-100 print:text-black">
                <td className="p-4 text-right">إجمالي المجموع</td>
                <td className="p-4 text-slate-400 print:text-slate-600">-</td>
                <td className="p-4 text-slate-200 print:text-black">{totalBasicSalaries.toLocaleString()} د.ع</td>
                <td className="p-4 text-emerald-450 print:text-green-800">+ {totalBonuses.toLocaleString()} د.ع</td>
                <td className="p-4 text-amber-500 print:text-amber-800">- {totalAttendanceDeductions.toLocaleString()} د.ع</td>
                <td className="p-4 text-rose-400 print:text-red-800">- {totalOtherDeductions.toLocaleString()} د.ع</td>
                <td className="p-4 text-orange-400 print:text-orange-900">- {totalLoans.toLocaleString()} د.ع</td>
                <td className="p-4 text-teal-300 text-sm bg-teal-900/20 print:bg-green-50 print:text-green-900">
                  {totalNetSalaries.toLocaleString()} د.ع
                </td>
                <td className="p-4 print:hidden"></td>
              </tr>
            </tfoot>
          </table>
        </div>

        {/* Print-Only Signature Block */}
        <div className="hidden print:block mt-16 text-slate-900 text-right font-sans" dir="rtl">
          <div className="grid grid-cols-3 gap-8 text-center text-xs">
            <div className="flex flex-col items-center">
              <span className="font-bold text-slate-600 mb-12">توقيع المحاسب المالي</span>
              <div className="w-40 border-b border-slate-400"></div>
            </div>
            <div className="flex flex-col items-center">
              <span className="font-bold text-slate-600 mb-12">توقيع مدير الموارد البشرية</span>
              <div className="w-40 border-b border-slate-400"></div>
            </div>
            <div className="flex flex-col items-center">
              <span className="font-bold text-slate-600 mb-12">اعتماد الإدارة العامة</span>
              <div className="w-40 border-b border-slate-400"></div>
            </div>
          </div>
        </div>
      </div>

      {/* Add Bonus / Deduction Modal */}
      {showAddBDModal && selectedEmpForBD && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md">
          <div className="relative w-full max-w-md bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 animate-glass text-right">
            <div className={`absolute top-0 inset-x-0 h-1 bg-gradient-to-r ${bdType === 'bonus' ? 'from-emerald-500 to-teal-500' : 'from-rose-500 to-red-500'}`}></div>
            
            <h3 className="text-lg font-bold text-white mb-6">إضافة تسوية مالية يدوية: {selectedEmpForBD.full_name}</h3>
            
            <form onSubmit={handleAddBonusDeduction} className="space-y-4">
              <div className="flex gap-4">
                <label className={`flex-1 flex flex-col items-center justify-center gap-2 p-4 rounded-2xl border-2 cursor-pointer transition-all ${bdType === 'bonus' ? 'border-emerald-500 bg-emerald-500/10' : 'border-slate-800 bg-slate-950/50'}`}>
                  <input type="radio" className="hidden" checked={bdType === 'bonus'} onChange={() => setBdType('bonus')} />
                  <TrendingUp className={`w-6 h-6 ${bdType === 'bonus' ? 'text-emerald-400' : 'text-slate-500'}`} />
                  <span className={`text-xs font-bold ${bdType === 'bonus' ? 'text-emerald-400' : 'text-slate-400'}`}>مكافأة (+)</span>
                </label>
                <label className={`flex-1 flex flex-col items-center justify-center gap-2 p-4 rounded-2xl border-2 cursor-pointer transition-all ${bdType === 'deduction' ? 'border-rose-500 bg-rose-500/10' : 'border-slate-800 bg-slate-950/50'}`}>
                  <input type="radio" className="hidden" checked={bdType === 'deduction'} onChange={() => setBdType('deduction')} />
                  <TrendingDown className={`w-6 h-6 ${bdType === 'deduction' ? 'text-rose-400' : 'text-slate-500'}`} />
                  <span className={`text-xs font-bold ${bdType === 'deduction' ? 'text-rose-400' : 'text-slate-400'}`}>خصم يدوي (-)</span>
                </label>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">المبلغ (د.ع)</label>
                <input
                  type="text"
                  required
                  value={bdAmount || ''}
                  onChange={(e) => setBdAmount(Number(e.target.value.replace(/\D/g, '')))}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
                  dir="ltr"
                  placeholder="مثال: 25000"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">السبب / البيان</label>
                <input
                  type="text"
                  required
                  value={bdReason}
                  onChange={(e) => setBdReason(e.target.value)}
                  placeholder="مثال: تسوية ساعات إضافية، عقوبة إدارية..."
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 mt-2 border-t border-slate-800">
                <button type="button" onClick={() => setShowAddBDModal(false)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
                <button
                  type="submit"
                  disabled={actionLoading === 'add_bd'}
                  className={`px-6 py-2 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 ${bdType === 'bonus' ? 'bg-emerald-600 hover:bg-emerald-500' : 'bg-rose-600 hover:bg-rose-500'}`}
                >
                  {actionLoading === 'add_bd' ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>تأكيد وحفظ</span>}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Attendance Breakdown details modal */}
      {selectedEmpIdForBreakdown && selectedEmpForBreakdown && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
          <div className="relative w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 text-right animate-glass my-8">
            <button 
              onClick={() => setSelectedEmpIdForBreakdown(null)}
              className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
            >
              <X className="w-4 h-4" />
            </button>

            <h3 className="text-md font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
              <CalendarRange className="w-5 h-5 text-teal-400" />
              <span>كشف حضور وخصومات الموظف: {selectedEmpForBreakdown.full_name}</span>
            </h3>

            {/* Attendance Stats Cards */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-slate-500 block mb-1">أيام العمل المجدولة</span>
                <span className="text-sm font-black text-white">{selectedEmpForBreakdown.scheduledWorkDays} يوم</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-emerald-400 block mb-1">الحضور والالتزام</span>
                <span className="text-sm font-black text-emerald-400">
                  {selectedEmpForBreakdown.presentsCount} حضور 
                  {selectedEmpForBreakdown.latesCount > 0 && ` (${selectedEmpForBreakdown.latesCount} متأخر)`}
                  {selectedEmpForBreakdown.earlyExitsCount > 0 && ` (${selectedEmpForBreakdown.earlyExitsCount} خروج مبكر)`}
                </span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-amber-500 block mb-1">إجمالي غيابات الخصم</span>
                <span className="text-sm font-black text-amber-500">{selectedEmpForBreakdown.absencesCount} يوم</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-blue-400 block mb-1">إجازات معتمدة</span>
                <span className="text-sm font-black text-blue-400">{selectedEmpForBreakdown.paidLeavesCount} يوم</span>
              </div>
            </div>

            {/* Calculations logic breakdown card */}
            <div className="p-4 bg-teal-950/15 border border-teal-500/20 rounded-2xl space-y-2 mb-6">
              <span className="text-xs font-bold text-white flex items-center gap-1.5 mb-2">
                <Info className="w-4 h-4 text-teal-400" />
                <span>تفاصيل الاحتساب الجاري للخصم المعتمد:</span>
              </span>
              <div className="text-xs text-slate-350 space-y-1.5 leading-relaxed font-medium">
                <p>• أجرة اليوم الواحد = الراتب الأساسي ({selectedEmpForBreakdown.basic.toLocaleString()} د.ع) ÷ 30 = <span className="font-mono text-teal-400 font-bold">{Math.round(selectedEmpForBreakdown.basic / 30).toLocaleString()} د.ع/يوم</span></p>
                {selectedEmpForBreakdown.absencesCount > 0 && (
                  <p>• خصم الغياب المطبق = {selectedEmpForBreakdown.absencesCount} أيام غياب × أجرة اليوم الكامل = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.absenceDeduction.toLocaleString()} د.ع</span></p>
                )}
                {selectedEmpForBreakdown.halfDaysCount > 0 && (
                  <p>• خصم أنصاف الأيام = {selectedEmpForBreakdown.halfDaysCount} أيام × نصف أجرة يوم = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.halfDayDeduction.toLocaleString()} د.ع</span></p>
                )}
                {selectedEmpForBreakdown.totalLateMinutes > 0 && (
                  <p>• خصم التأخير المطبق = {selectedEmpForBreakdown.totalLateMinutes} دقيقة تأخر × (أجرة اليوم ÷ 480 دقيقة) = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.latenessDeduction.toLocaleString()} د.ع</span></p>
                )}
                {selectedEmpForBreakdown.totalEarlyExitMinutes > 0 && (
                  <p>• خصم الخروج المبكر المطبق = {selectedEmpForBreakdown.totalEarlyExitMinutes} دقيقة خروج مبكر × (أجرة اليوم ÷ 480 دقيقة) = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.earlyExitDeduction.toLocaleString()} د.ع</span></p>
                )}
                <p className="border-t border-slate-800 pt-2 font-bold text-white">
                  • إجمالي خصومات الدوام والغياب المطبقة = <span className="font-mono text-teal-300 text-sm font-black">{selectedEmpForBreakdown.totalAttendanceDeductions.toLocaleString()} د.ع</span>
                </p>
              </div>
            </div>

            {/* Bonuses & Other Deductions Detailed Cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
              {/* 1. قسم المكافآت والزيادات */}
              <div className="p-4 bg-emerald-950/20 border border-emerald-500/20 rounded-2xl">
                <div className="flex items-center justify-between mb-3 border-b border-emerald-500/10 pb-2">
                  <span className="text-xs font-bold text-emerald-400 flex items-center gap-1.5">
                    <TrendingUp className="w-4 h-4" />
                    <span>المكافآت والزيادات ({selectedEmpForBreakdown.totalBonuses.toLocaleString()} د.ع)</span>
                  </span>
                  <button
                    onClick={() => {
                      setSelectedEmpForBD(selectedEmpForBreakdown);
                      setBdType('bonus');
                      setBdAmount(0);
                      setBdReason('');
                      setShowAddBDModal(true);
                    }}
                    className="text-[10px] font-bold bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-400 px-2 py-0.5 rounded-lg border border-emerald-500/20 flex items-center gap-1 transition-all cursor-pointer"
                  >
                    <Plus className="w-3 h-3" />
                    <span>إضافة مكافأة</span>
                  </button>
                </div>

                {selectedEmpForBreakdown.bonusesList && selectedEmpForBreakdown.bonusesList.length > 0 ? (
                  <div className="space-y-2 max-h-[140px] overflow-y-auto">
                    {selectedEmpForBreakdown.bonusesList.map((b: BonusDeduction, idx: number) => (
                      <div key={idx} className="p-2 bg-slate-950/40 rounded-xl border border-emerald-500/10 text-xs flex justify-between items-start gap-2">
                        <div>
                          <div className="text-white font-bold">{b.reason || 'مكافأة تشجيعية'}</div>
                          <div className="text-[10px] text-slate-400 mt-0.5">التاريخ: {b.issue_date || '-'}</div>
                        </div>
                        <span className="font-mono text-emerald-400 font-bold text-xs shrink-0">
                          + {Number(b.amount).toLocaleString()} د.ع
                        </span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-4 text-xs text-slate-500">
                    لا توجد مكافآت مسجلة لهذا الموظف خلال هذه الدورة
                  </div>
                )}
              </div>

              {/* 2. قسم الخصومات والجزاءات الإدارية */}
              <div className="p-4 bg-rose-950/20 border border-rose-500/20 rounded-2xl">
                <div className="flex items-center justify-between mb-3 border-b border-rose-500/10 pb-2">
                  <span className="text-xs font-bold text-rose-400 flex items-center gap-1.5">
                    <TrendingDown className="w-4 h-4" />
                    <span>الخصومات والجزاءات ({((selectedEmpForBreakdown.totalDeductions || 0) - (selectedEmpForBreakdown.totalAttendanceDeductions || 0)).toLocaleString()} د.ع)</span>
                  </span>
                  <button
                    onClick={() => {
                      setSelectedEmpForBD(selectedEmpForBreakdown);
                      setBdType('deduction');
                      setBdAmount(0);
                      setBdReason('');
                      setShowAddBDModal(true);
                    }}
                    className="text-[10px] font-bold bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 px-2 py-0.5 rounded-lg border border-rose-500/20 flex items-center gap-1 transition-all cursor-pointer"
                  >
                    <Plus className="w-3 h-3" />
                    <span>إضافة خصم</span>
                  </button>
                </div>

                {selectedEmpForBreakdown.otherDeductionsList && selectedEmpForBreakdown.otherDeductionsList.length > 0 ? (
                  <div className="space-y-2 max-h-[140px] overflow-y-auto">
                    {selectedEmpForBreakdown.otherDeductionsList.map((d: BonusDeduction, idx: number) => (
                      <div key={idx} className="p-2 bg-slate-950/40 rounded-xl border border-rose-500/10 text-xs flex justify-between items-start gap-2">
                        <div>
                          <div className="text-white font-bold">{d.reason || 'خصم إداري'}</div>
                          <div className="text-[10px] text-slate-400 mt-0.5">التاريخ: {d.issue_date || '-'}</div>
                        </div>
                        <span className="font-mono text-rose-400 font-bold text-xs shrink-0">
                          - {Number(d.amount).toLocaleString()} د.ع
                        </span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-4 text-xs text-slate-500">
                    لا توجد خصومات إدارية مسجلة لهذا الموظف خلال هذه الدورة
                  </div>
                )}
              </div>
            </div>

            {/* 3. قسم خصومات أقساط السلف إذا وجدت */}
            {selectedEmpForBreakdown.loanDeduction > 0 && (
              <div className="p-3 bg-amber-950/20 border border-amber-500/20 rounded-2xl mb-6 flex justify-between items-center text-xs">
                <div className="flex items-center gap-2">
                  <Banknote className="w-4 h-4 text-amber-400" />
                  <span className="font-bold text-white">قسط السلفة المستحق لهذا الشهر:</span>
                </div>
                <span className="font-mono font-bold text-amber-400 text-sm">
                  - {selectedEmpForBreakdown.loanDeduction.toLocaleString()} د.ع
                </span>
              </div>
            )}

            {/* Calendar logs list */}
            <h4 className="text-xs font-bold text-slate-400 mb-3 flex items-center justify-between">
              <span className="flex items-center gap-1">
                <Clock className="w-4 h-4" />
                <span>يوميات وسجلات الدورة المالية بالتفصيل (من {startDate} إلى {endDate}):</span>
              </span>
              <span className="text-[10px] text-amber-400 font-medium">
                * يمكنك الضغط على زر الإعفاء لإلغاء خصم غياب الموظف أو احتسابه يدوياً
              </span>
            </h4>
            
            <div className="overflow-y-auto max-h-[250px] border border-slate-800 rounded-2xl bg-slate-950/20 divide-y divide-slate-800/80">
              {selectedEmpForBreakdown.detailLogs.map((log: DetailLog, idx: number) => (
                <div key={idx} className="p-3 flex items-center justify-between text-xs hover:bg-slate-900/40 transition-colors">
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-slate-400 font-semibold">{log.date}</span>
                    <span className={`px-2 py-0.5 rounded-md font-bold text-[9px] ${
                      log.status.includes('حاضر') || log.status.includes('معفى') ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/15' :
                      log.status.includes('غياب') ? 'bg-rose-500/10 text-rose-400 border border-rose-500/15' :
                      log.status.includes('إجازة') ? 'bg-blue-500/10 text-blue-400 border border-blue-500/15' :
                      'bg-slate-800 text-slate-400'
                    }`}>
                      {log.status}
                    </span>
                  </div>
                  
                  <div className="flex items-center gap-6">
                    <span className="text-slate-400">
                      {log.time !== '-' ? `وقت البصمة: ${log.time}` : ''}
                    </span>
                    
                    {log.isAbsenceDay ? (
                      <button
                        onClick={() => toggleExcuseDay(selectedEmpIdForBreakdown, log.date)}
                        className={`px-3 py-1 rounded-xl font-bold text-[10px] transition-all cursor-pointer ${
                          log.isExcused 
                            ? 'bg-rose-550/20 hover:bg-rose-550/30 text-rose-400 border border-rose-500/30' 
                            : 'bg-emerald-550/20 hover:bg-emerald-550/30 text-emerald-400 border border-emerald-500/30'
                        }`}
                      >
                        {log.isExcused ? 'إلغاء الإعفاء (احتساب غياب)' : 'إعفاء (إلغاء الخصم)'}
                      </button>
                    ) : (
                      <span className="text-slate-500 text-[11px] font-medium min-w-[200px] text-left">
                        {log.note}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>

            <div className="flex justify-between items-center pt-6 mt-6 border-t border-slate-800">
              <button 
                onClick={() => window.print()}
                className="px-4 py-2.5 bg-slate-800 hover:bg-slate-700 text-teal-300 rounded-xl text-xs font-bold transition-all border border-slate-700 flex items-center gap-2 cursor-pointer"
              >
                <Printer className="w-4 h-4" />
                <span>طباعة كشف راتب الموظف 📄</span>
              </button>
              <button 
                onClick={() => setSelectedEmpIdForBreakdown(null)}
                className="px-6 py-2.5 bg-slate-950 hover:bg-slate-900 text-white rounded-xl text-xs font-bold transition-all border border-slate-800 cursor-pointer"
              >
                موافق وإغلاق
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Branch Calculation Modal */}
      {showBulkModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/85 backdrop-blur-md">
          <div className="relative w-full max-w-lg bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 animate-glass text-right">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-cyan-500"></div>
            
            <button 
              onClick={() => setShowBulkModal(false)}
              className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
            >
              <X className="w-4 h-4" />
            </button>

            <h3 className="text-lg font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
              <Banknote className="w-5 h-5 text-teal-400" />
              <span>احتساب واعتماد رواتب فرع: {branchName}</span>
            </h3>
            
            <div className="py-4 space-y-4">
              <p className="text-xs text-slate-400">
                تقوم هذه العملية باحتساب رواتب جميع موظفي الفرع المحدّد للفترة المالية الحالية (<span className="text-white font-bold">{startDate}</span> إلى <span className="text-white font-bold">{endDate}</span>) واعتماد كشوف رواتبهم بشكل نهائي دفعة واحدة.
              </p>

              {pendingBranchEmps.length === 0 ? (
                <div className="p-6 bg-emerald-950/10 border border-emerald-500/20 rounded-2xl text-center space-y-2">
                  <CheckCircle className="w-8 h-8 text-emerald-400 mx-auto" />
                  <p className="text-sm font-bold text-white">كل رواتب الموظفين معتمدة! ✅</p>
                  <p className="text-xs text-slate-400">تم بالفعل اعتماد كشوف الرواتب لجميع موظفي هذا الفرع لشهر {selectedMonth}.</p>
                </div>
              ) : (
                <>
                  {/* Summary Stats Grid */}
                  <div className="grid grid-cols-2 gap-3">
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-slate-500 block">عدد الموظفين المعلقين</span>
                      <span className="text-md font-bold text-white">{pendingBranchEmps.length} موظف</span>
                    </div>
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-slate-500 block">إجمالي الرواتب الأساسية</span>
                      <span className="text-md font-bold text-slate-200">{totalBranchBase.toLocaleString()} د.ع</span>
                    </div>
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-emerald-500 block">إجمالي المكافآت (+)</span>
                      <span className="text-md font-bold text-emerald-400">+{totalBranchBonuses.toLocaleString()} د.ع</span>
                    </div>
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-amber-500 block">إجمالي الخصومات والغياب (-)</span>
                      <span className="text-md font-bold text-amber-500">-{totalBranchDeductions.toLocaleString()} د.ع</span>
                    </div>
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-orange-400 block">إجمالي خصومات السلف (-)</span>
                      <span className="text-md font-bold text-orange-400">-{totalBranchLoans.toLocaleString()} د.ع</span>
                    </div>
                    <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80 col-span-2 bg-teal-950/10 border-teal-500/20">
                      <span className="text-[10px] text-teal-400 block font-bold font-sans">إجمالي صافي الرواتب المستحق صرفها (Net)</span>
                      <span className="text-xl font-black text-teal-300">{totalBranchNet.toLocaleString()} د.ع</span>
                    </div>
                  </div>

                  <div className="p-3 bg-amber-950/10 border border-amber-500/20 rounded-xl text-xs text-amber-400 flex items-start gap-2">
                    <Info className="w-4 h-4 shrink-0 mt-0.5" />
                    <span>
                      تنبيّه: بعد تأكيد الاعتماد، سيتم إرسال إشعارات فورية لجميع الموظفين البالغ عددهم ({pendingBranchEmps.length}) بكشوف رواتبهم الجديدة وتحديث حالة السلف والخصومات تلقائياً.
                    </span>
                  </div>
                </>
              )}
            </div>

            <div className="flex justify-end gap-3 pt-6 border-t border-slate-800">
              <button 
                type="button" 
                onClick={() => setShowBulkModal(false)} 
                className="px-4 py-2 text-slate-400 hover:text-white"
              >
                إلغاء
              </button>
              {pendingBranchEmps.length > 0 && (
                <button
                  type="button"
                  disabled={actionLoading === 'bulk_generate'}
                  onClick={() => handleBulkGenerateSlips(pendingBranchEmps)}
                  className="px-6 py-2.5 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all flex items-center gap-2 cursor-pointer active:scale-95"
                >
                  {actionLoading === 'bulk_generate' ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <>
                      <CheckCircle className="w-4 h-4" />
                      <span>اعتماد وصرف رواتب الفرع بالكامل</span>
                    </>
                  )}
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
