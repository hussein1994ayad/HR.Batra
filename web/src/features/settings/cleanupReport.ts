// تقرير معاينة التنظيف (Excel) قبل التنفيذ: شنو راح ينحذف، شنو مستثنى وليش، والمساحة التقريبية.
// ينزل من زر «تقرير المعاينة» بشاشة التنظيف حتى ينراجع أو ينحفظ قبل أي حذف.

import * as XLSX from 'xlsx';
import { payrollMonthName } from '@/features/payroll/period';
import { loanRef } from '@/features/loans/logic';
import { attendanceBlockers, formatBytes } from './logic';
import type { CleanupPreview, LoansCleanupPreview } from './types';

/** صفوف التقرير (مفصولة عن الملف حتى تنفحص). */
export function cleanupReportSheets(period: CleanupPreview | null, loans: LoansCleanupPreview | null) {
  const sheets: { name: string; rows: Record<string, string | number>[] }[] = [];
  if (period) {
    const blockers = attendanceBlockers(period);
    sheets.push({
      name: 'المسير',
      rows: [
        { 'البند': 'المسير', 'القيمة': `رواتب ${payrollMonthName(period.month)}` },
        { 'البند': 'الفترة', 'القيمة': `${period.start_date} → ${period.end_date}` },
        { 'البند': 'حالة المسير', 'القيمة': period.checks.closed ? 'مغلق' : 'مفتوح' },
        { 'البند': 'المسير اللي بعده', 'القيمة': period.checks.next_delivered ? 'مغلق وتسلّمت رواتبه' : period.checks.next_closed ? 'مغلق، التسليم ما تأكد' : 'مفتوح' },
        { 'البند': 'حركات تنتظر قرار', 'القيمة': period.checks.pending_decisions },
        { 'البند': 'سجلات الحضور والبصمات', 'القيمة': period.counts.attendance },
        { 'البند': 'سجلات التتبع (GPS + وقفات + مخالفات)', 'القيمة': period.counts.tracking + period.counts.stops + period.counts.violations },
        { 'البند': 'الإشعارات', 'القيمة': period.counts.notifications },
        { 'البند': 'المساحة التقريبية', 'القيمة': formatBytes(period.bytes.attendance + period.bytes.tracking + period.bytes.notifications) },
        { 'البند': 'الحضور ينحذف هسه؟', 'القيمة': period.can.attendance ? 'نعم' : `لا — ${blockers.join(' ')}` },
      ],
    });
    if (period.pending_list.length > 0) {
      sheets.push({
        name: 'مستثنى - حركات معلّقة',
        rows: period.pending_list.map((e) => ({ 'الموظف': e.employee, 'التاريخ': e.date, 'النوع': e.type, 'المبلغ': Number(e.amount), 'السبب': 'تنتظر قرار (خصم أو إعفاء)' })),
      });
    }
  }
  if (loans) {
    sheets.push({
      name: 'سلف تتأرشف',
      rows: loans.settled.map((l) => ({ 'رقم السلفة': loanRef(l.loan_no), 'الموظف': l.employee, 'المبلغ': Number(l.amount), 'تاريخ التسوية': (l.settled_at ?? '').slice(0, 10) })),
    });
    sheets.push({
      name: 'سلف مستثناة',
      rows: loans.excluded.map((l) => ({ 'رقم السلفة': loanRef(l.loan_no), 'الموظف': l.employee, 'المبلغ': Number(l.amount), 'الباقي': Number(l.remaining), 'السبب': l.reason })),
    });
    sheets.push({
      name: 'طلبات مرفوضة قديمة',
      rows: loans.requests.map((l) => ({ 'رقم الطلب': loanRef(l.loan_no), 'الموظف': l.employee, 'المبلغ': Number(l.amount), 'الحالة': l.status === 'rejected' ? 'مرفوض' : 'ملغى', 'تاريخ الطلب': l.created_at.slice(0, 10) })),
    });
  }
  return sheets;
}

export function downloadCleanupReport(period: CleanupPreview | null, loans: LoansCleanupPreview | null): void {
  const wb = XLSX.utils.book_new();
  for (const sheet of cleanupReportSheets(period, loans)) {
    const rows = sheet.rows.length > 0 ? sheet.rows : [{ 'ملاحظة': 'ماكو سجلات' }];
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows), sheet.name);
  }
  XLSX.writeFile(wb, `معاينة_التنظيف_${period?.month ?? 'السلف'}_${new Date().toISOString().slice(0, 10)}.xlsx`);
}
