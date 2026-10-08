// ملفات Excel للمساعد — نفس هوية تقارير النظام (mobile/lib/core/services/excel/attendance_report_excel.dart):
// عنوان داكن، شريط فرعي أخضر مزرق، رأس جدول رمادي، ألوان الحالات نفسها، اتجاه من اليمين لليسار.
// الأرقام كلها من دوال القاعدة (assistant_attendance_log / assistant_payroll) — الذكاء ما يكتب أرقام بالملف.

import ExcelJS from "npm:exceljs@4.4.0";

const C = {
  title: "0F172A",
  band: "0D9488",
  header: "334155",
  border: "CBD5E1",
  white: "FFFFFF",
  muted: "64748B",
  zebra: "F8FAFC",
};

// الحالة ← (خلفية، نص)
const STATUS: Record<string, [string, string]> = {
  "حاضر": ["DCFCE7", "166534"],
  "متأخر": ["FEF9C3", "854D0E"],
  "خروج مبكر": ["FFEDD5", "9A3412"],
  "غياب": ["FEE2E2", "991B1B"],
  "بصمة ناقصة": ["FEF3C7", "92400E"],
  "إجازة": ["E0F2FE", "075985"],
  "عطلة رسمية": ["F1F5F9", "475569"],
  "عطلة أسبوعية": ["F1F5F9", "475569"],
  "لم يحن بعد": ["FFFFFF", "94A3B8"],
  "خارج فترة الخدمة": ["FFFFFF", "94A3B8"],
};
const DECISION: Record<string, [string, string]> = {
  "مخصوم": ["FEE2E2", "991B1B"],
  "محتسب": ["FEE2E2", "991B1B"],
  "معفى": ["DCFCE7", "166534"],
  "بانتظار القرار": ["FEF9C3", "854D0E"],
};
const WEEKDAYS = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
const EVENT_LABELS: Record<string, string> = {
  absence: "غياب", late: "تأخير", early_leave: "خروج مبكر", missing_punch: "بصمة ناقصة", unpaid_leave: "إجازة بدون راتب",
  paid_leave: "إجازة مدفوعة", overtime: "ساعات إضافية", manual_deduction: "خصم", bonus: "مكافأة", allowance: "مخصصات",
  advance: "سلفة", adjustment: "تسوية", other: "أخرى",
};

const fill = (hex: string): ExcelJS.Fill => ({ type: "pattern", pattern: "solid", fgColor: { argb: "FF" + hex } });
const thin = { style: "thin" as const, color: { argb: "FF" + C.border } };
const money = (n: unknown) => Math.round(Number(n ?? 0));

export interface AttendanceLog {
  employee: { name: string; code?: string | null; branch?: string | null };
  from: string;
  to: string;
  summary: Record<string, number | string | null>;
  days: Array<{
    date: string; weekday: number; status: string; check_in?: string | null; check_out?: string | null;
    late_minutes?: number | string; early_minutes?: number | string; holiday?: string | null; leave?: string | null;
    decision?: string | null; deducted?: number | string;
    events?: Array<{ type: string; reason?: string | null; decision?: string }>;
  }>;
}

export interface PayrollDetails {
  employee: string;
  month: string;
  period?: { from: string; to: string; status: string };
  summary?: Record<string, unknown>;
  events: Array<{ date: string; type: string; minutes?: number; days?: number; amount: number; direction: number;
    decision: string; reason?: string | null; carried_from?: string | null }>;
  loan_installments?: Array<{ due_date: string; amount: number; paid: boolean }>;
  message?: string;
}

function newSheet(wb: ExcelJS.Workbook, name: string, widths: number[]): ExcelJS.Worksheet {
  const ws = wb.addWorksheet(name, { views: [{ rightToLeft: true, showGridLines: false }] });
  ws.columns = widths.map((width) => ({ width }));
  return ws;
}

function titleRows(ws: ExcelJS.Worksheet, cols: number, title: string, subtitle: string) {
  ws.mergeCells(1, 1, 1, cols);
  const t = ws.getCell(1, 1);
  t.value = title;
  t.font = { name: "Arial", size: 15, bold: true, color: { argb: "FF" + C.white } };
  t.fill = fill(C.title);
  t.alignment = { horizontal: "center", vertical: "middle" };
  ws.getRow(1).height = 32;

  ws.mergeCells(2, 1, 2, cols);
  const s = ws.getCell(2, 1);
  s.value = subtitle;
  s.font = { name: "Arial", size: 10, color: { argb: "FF" + C.white } };
  s.fill = fill(C.band);
  s.alignment = { horizontal: "center", vertical: "middle" };
  ws.getRow(2).height = 20;
}

function headerRow(ws: ExcelJS.Worksheet, row: number, labels: string[]) {
  const r = ws.getRow(row);
  labels.forEach((label, i) => {
    const c = r.getCell(i + 1);
    c.value = label;
    c.font = { name: "Arial", size: 10, bold: true, color: { argb: "FF" + C.white } };
    c.fill = fill(C.header);
    c.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    c.border = { top: thin, bottom: thin, left: thin, right: thin };
  });
  r.height = 28;
}

function bodyCell(c: ExcelJS.Cell, zebra: boolean) {
  c.font = { name: "Arial", size: 10, color: { argb: "FF0F172A" } };
  c.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
  c.border = { top: thin, bottom: thin, left: thin, right: thin };
  if (zebra) c.fill = fill(C.zebra);
}

function paint(c: ExcelJS.Cell, colors: [string, string] | undefined) {
  if (!colors) return;
  c.fill = fill(colors[0]);
  c.font = { ...c.font, bold: true, color: { argb: "FF" + colors[1] } };
}

function kpiTable(ws: ExcelJS.Worksheet, startRow: number, rows: Array<[string, string | number, [string, string]?]>) {
  rows.forEach(([label, value, colors], i) => {
    const r = ws.getRow(startRow + i);
    const a = r.getCell(1);
    const b = r.getCell(2);
    a.value = label;
    b.value = value;
    for (const c of [a, b]) bodyCell(c, i % 2 === 1);
    a.font = { ...a.font, bold: true };
    a.alignment = { horizontal: "right", vertical: "middle" };
    if (colors) paint(b, colors);
    if (typeof value === "number") b.numFmt = "#,##0";
    r.height = 22;
  });
}

const issued = () => new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Baghdad" });

// ---------------------------------------------------------------------
// أوراق قابلة لإعادة الاستعمال (موظف، فرع، ملف شامل)
// ---------------------------------------------------------------------

/** اسم ورقة صالح (أقصاه 31 حرف، بدون رموز ممنوعة، وغير مكرر). */
function sheetName(wb: ExcelJS.Workbook, wanted: string): string {
  const base = wanted.replace(/[\\/?*[\]:]/g, " ").trim().slice(0, 28) || "ورقة";
  let name = base;
  for (let i = 2; wb.getWorksheet(name); i++) name = `${base.slice(0, 25)} ${i}`;
  return name;
}

function totalRow(ws: ExcelJS.Worksheet, row: number, values: unknown[], moneyCols: number[] = []) {
  const r = ws.getRow(row);
  r.values = values as ExcelJS.CellValue[];
  r.eachCell({ includeEmpty: true }, (c) => {
    bodyCell(c, false);
    c.font = { name: "Arial", size: 10, bold: true, color: { argb: "FF" + C.white } };
    c.fill = fill(C.title);
  });
  for (const col of moneyCols) r.getCell(col).numFmt = "#,##0";
}

/** ورقة سجل الدوام يوم بيوم لموظف. */
function addAttendanceSheet(wb: ExcelJS.Workbook, log: AttendanceLog, name = "سجل الدوام") {
  const headers = ["#", "التاريخ", "اليوم", "الحالة", "الحضور", "الانصراف", "تأخير (د)", "خروج مبكر (د)",
    "إجازة / عطلة", "القرار", "المخصوم (د.ع)", "الملاحظة"];
  const ws = newSheet(wb, sheetName(wb, name), [5, 12, 11, 14, 10, 10, 10, 12, 20, 15, 14, 34]);
  const e = log.employee;
  titleRows(ws, headers.length, `سجل دوام — ${e.name}`,
    `الفرع: ${e.branch ?? "—"}   ·   الكود: ${e.code ?? "—"}   ·   الفترة: ${log.from} ← ${log.to}   ·   أُصدر: ${issued()}`);
  headerRow(ws, 4, headers);
  log.days.forEach((d, i) => {
    const note = (d.events ?? []).map((x) => x.reason).filter(Boolean).join(" · ");
    const row = ws.getRow(5 + i);
    row.values = [
      i + 1, d.date, WEEKDAYS[d.weekday] ?? "", d.status, d.check_in ?? "", d.check_out ?? "",
      Number(d.late_minutes ?? 0) || "", Number(d.early_minutes ?? 0) || "", d.holiday ?? d.leave ?? "",
      d.decision ?? "", money(d.deducted) || "", note,
    ];
    row.eachCell({ includeEmpty: true }, (c) => bodyCell(c, i % 2 === 1));
    paint(row.getCell(4), STATUS[d.status]);
    if (d.decision) paint(row.getCell(10), DECISION[d.decision]);
    row.getCell(11).numFmt = "#,##0";
    row.getCell(12).alignment = { horizontal: "right", vertical: "middle", wrapText: true };
    row.height = 20;
  });
  const s = log.summary;
  totalRow(ws, 5 + log.days.length, ["", "المجموع", "", "", "", "", Number(s.late_minutes ?? 0), "", "", "", money(s.deducted_total), ""], [11]);
  ws.views = [{ rightToLeft: true, showGridLines: false, state: "frozen", ySplit: 4 }];
  ws.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4 + log.days.length, column: headers.length } };
}

/** ورقة ملخص الدوام لموظف (أرقام بخانات ملونة). */
function addAttendanceSummarySheet(wb: ExcelJS.Workbook, log: AttendanceLog, name = "الملخص") {
  const s = log.summary;
  const sum = newSheet(wb, sheetName(wb, name), [28, 18]);
  titleRows(sum, 2, `ملخص الدوام — ${log.employee.name}`, `${log.from} ← ${log.to}`);
  kpiTable(sum, 4, [
    ["أيام الحضور", Number(s.present ?? 0), STATUS["حاضر"]],
    ["منها متأخر", Number(s.late ?? 0), STATUS["متأخر"]],
    ["منها خروج مبكر", Number(s.early_leave ?? 0), STATUS["خروج مبكر"]],
    ["أيام الغياب", Number(s.absent ?? 0), STATUS["غياب"]],
    ["بصمة ناقصة", Number(s.missing_punch ?? 0), STATUS["بصمة ناقصة"]],
    ["أيام الإجازة", Number(s.leave ?? 0), STATUS["إجازة"]],
    ["مجموع دقائق التأخير", Number(s.late_minutes ?? 0)],
    ["أيام مخصومة", Number(s.deducted_days ?? 0), DECISION["مخصوم"]],
    ["أيام معفاة", Number(s.excused_days ?? 0), DECISION["معفى"]],
    ["بانتظار القرار", Number(s.pending_days ?? 0), DECISION["بانتظار القرار"]],
    ["مجموع المخصوم (د.ع)", money(s.deducted_total), DECISION["مخصوم"]],
  ]);
}

/** ورقة تفاصيل راتب شهر: الملخص + الحركات بقرارها + أقساط السلف. */
function addPayrollSheet(wb: ExcelJS.Workbook, p: PayrollDetails, name = "تفاصيل الراتب") {
  const headers = ["#", "التاريخ", "النوع", "المدة", "المبلغ (د.ع)", "خصم / إضافة", "القرار", "الملاحظة", "مرحّل من"];
  const ws = newSheet(wb, sheetName(wb, name), [5, 12, 16, 12, 14, 12, 15, 34, 11]);
  titleRows(ws, headers.length, `تفاصيل راتب ${p.month} — ${p.employee}`,
    p.period ? `الفترة: ${p.period.from} ← ${p.period.to}   ·   المسير: ${p.period.status === "open" ? "مفتوح" : "مغلق"}   ·   أُصدر: ${issued()}`
      : (p.message ?? ""));
  const s = (p.summary ?? {}) as Record<string, unknown>;
  const slip = s.slip as Record<string, unknown> | null | undefined;
  kpiTable(ws, 4, [
    ["الراتب الأساسي", money(slip?.basic_salary ?? s.basic)],
    ["الإضافات", money(slip?.allowances ?? s.earnings), DECISION["معفى"]],
    ["الخصومات", money(slip?.deductions ?? s.deductions), DECISION["مخصوم"]],
    ["أقساط السلف", money(slip?.loans_deduction ?? s.loans), DECISION["مخصوم"]],
    ["الصافي", money(slip?.net_salary ?? s.net), ["CCFBF1", "115E59"]],
    ["حركات بانتظار القرار", Number(s.pending_count ?? 0), DECISION["بانتظار القرار"]],
    ["الحالة", slip ? "صدر الكشف" : "قبل الاعتماد"],
  ]);
  const top = 12;
  headerRow(ws, top, headers);
  p.events.forEach((ev, i) => {
    const duration = ev.days ? `${ev.days} يوم` : ev.minutes ? `${ev.minutes} د` : "";
    const row = ws.getRow(top + 1 + i);
    row.values = [i + 1, ev.date, EVENT_LABELS[ev.type] ?? ev.type, duration, money(ev.amount),
      ev.direction > 0 ? "إضافة" : ev.direction < 0 ? "خصم" : "—", ev.decision, ev.reason ?? "", ev.carried_from ?? ""];
    row.eachCell({ includeEmpty: true }, (c) => bodyCell(c, i % 2 === 1));
    paint(row.getCell(7), DECISION[ev.decision]);
    row.getCell(5).numFmt = "#,##0";
    row.getCell(8).alignment = { horizontal: "right", vertical: "middle", wrapText: true };
  });
  const inst = p.loan_installments ?? [];
  if (inst.length) {
    const r0 = top + 2 + p.events.length;
    headerRow(ws, r0, ["#", "استحقاق القسط", "المبلغ (د.ع)", "الحالة"]);
    inst.forEach((li, i) => {
      const row = ws.getRow(r0 + 1 + i);
      row.values = [i + 1, li.due_date, money(li.amount), li.paid ? "مدفوع" : "يُخصم بهذا الشهر"];
      [1, 2, 3, 4].forEach((n) => bodyCell(row.getCell(n), i % 2 === 1));
      row.getCell(3).numFmt = "#,##0";
    });
  }
  ws.views = [{ rightToLeft: true, showGridLines: false, state: "frozen", ySplit: top }];
}

/** جدول بسيط بعنوان ورأس وصفوف (للسلف، الإجازات، رواتب الشهر...). */
function addTableSheet(wb: ExcelJS.Workbook, name: string, title: string, subtitle: string, headers: string[], widths: number[],
  rows: unknown[][], opts: { moneyCols?: number[]; total?: unknown[]; paintCol?: number } = {}) {
  const ws = newSheet(wb, sheetName(wb, name), widths);
  titleRows(ws, headers.length, title, subtitle);
  headerRow(ws, 4, headers);
  rows.forEach((values, i) => {
    const row = ws.getRow(5 + i);
    row.values = values as ExcelJS.CellValue[];
    row.eachCell({ includeEmpty: true }, (c) => bodyCell(c, i % 2 === 1));
    for (const col of opts.moneyCols ?? []) row.getCell(col).numFmt = "#,##0";
    if (opts.paintCol) {
      const v = String(values[opts.paintCol - 1] ?? "");
      paint(row.getCell(opts.paintCol), DECISION[v] ?? STATUS[v]);
    }
  });
  if (opts.total) totalRow(ws, 5 + rows.length, opts.total, opts.moneyCols);
  ws.views = [{ rightToLeft: true, showGridLines: false, state: "frozen", ySplit: 4 }];
  if (rows.length) ws.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4 + rows.length, column: headers.length } };
  return ws;
}

const newBook = () => {
  const wb = new ExcelJS.Workbook();
  wb.creator = "HR Pro";
  return wb;
};
const bytesOf = async (wb: ExcelJS.Workbook) => new Uint8Array(await wb.xlsx.writeBuffer());
const sumOf = (rows: unknown[][], col: number) => rows.reduce((a, r) => a + (Number(r[col - 1]) || 0), 0);

// ---------------------------------------------------------------------
// الملفات
// ---------------------------------------------------------------------

/** سجل دوام موظف يوم بيوم + ورقة ملخص. */
export async function buildAttendanceWorkbook(log: AttendanceLog): Promise<Uint8Array> {
  const wb = newBook();
  addAttendanceSheet(wb, log);
  addAttendanceSummarySheet(wb, log);
  return bytesOf(wb);
}

/** تفاصيل راتب شهر لموظف. */
export async function buildPayrollWorkbook(p: PayrollDetails): Promise<Uint8Array> {
  const wb = newBook();
  addPayrollSheet(wb, p);
  return bytesOf(wb);
}

export interface BranchAttendance { scope: string; from: string; to: string; employees: AttendanceLog[] }

/** سجل دوام فرع/الشركة: ورقة ملخص (صف لكل موظف) + ورقة لكل موظف. */
export async function buildBranchAttendanceWorkbook(r: BranchAttendance): Promise<Uint8Array> {
  const wb = newBook();
  const rows = r.employees.map((l, i) => {
    const s = l.summary;
    return [i + 1, l.employee.name, l.employee.code ?? "", l.employee.branch ?? "", Number(s.present ?? 0), Number(s.late ?? 0),
      Number(s.early_leave ?? 0), Number(s.absent ?? 0), Number(s.leave ?? 0), Number(s.missing_punch ?? 0),
      Number(s.late_minutes ?? 0), money(s.deducted_total)];
  });
  addTableSheet(wb, "الملخص", `سجل الدوام — ${r.scope}`, `الفترة: ${r.from} ← ${r.to}   ·   ${rows.length} موظف   ·   أُصدر: ${issued()}`,
    ["#", "الموظف", "الكود", "الفرع", "حضور", "متأخر", "خروج مبكر", "غياب", "إجازة", "بصمة ناقصة", "دقائق التأخير", "المخصوم (د.ع)"],
    [5, 24, 10, 16, 8, 8, 10, 8, 8, 10, 12, 14], rows,
    { moneyCols: [12], total: ["", "المجموع", "", "", sumOf(rows, 5), sumOf(rows, 6), sumOf(rows, 7), sumOf(rows, 8), sumOf(rows, 9),
      sumOf(rows, 10), sumOf(rows, 11), sumOf(rows, 12)] });
  for (const l of r.employees) addAttendanceSheet(wb, l, l.employee.name);
  return bytesOf(wb);
}

export interface PayrollRun {
  month: string;
  period?: { from: string; to: string; status: string };
  rows: Array<{ employee: string; branch?: string | null; basic: number; earnings: number; deductions: number; loans: number;
    net: number; absence_days?: number; late_minutes?: number; pending?: number; issued: boolean }>;
  message?: string;
}

/** رواتب كل الموظفين لشهر مسير + المجموع. */
export async function buildPayrollRunWorkbook(run: PayrollRun): Promise<Uint8Array> {
  const wb = newBook();
  const rows = (run.rows ?? []).map((r, i) => [i + 1, r.employee, r.branch ?? "", money(r.basic), money(r.earnings), money(r.deductions),
    money(r.loans), money(r.net), Number(r.absence_days ?? 0), Number(r.late_minutes ?? 0), Number(r.pending ?? 0),
    r.issued ? "صدر الكشف" : "قبل الاعتماد"]);
  addTableSheet(wb, "رواتب الشهر", `رواتب مسير ${run.month}`,
    run.period ? `الفترة: ${run.period.from} ← ${run.period.to}   ·   ${rows.length} موظف   ·   أُصدر: ${issued()}` : (run.message ?? ""),
    ["#", "الموظف", "الفرع", "الأساسي", "الإضافات", "الخصومات", "أقساط السلف", "الصافي", "غياب (يوم)", "تأخير (د)", "بانتظار قرار", "الحالة"],
    [5, 24, 16, 13, 12, 12, 12, 14, 10, 10, 11, 14], rows,
    { moneyCols: [4, 5, 6, 7, 8], total: ["", "المجموع", "", sumOf(rows, 4), sumOf(rows, 5), sumOf(rows, 6), sumOf(rows, 7), sumOf(rows, 8),
      sumOf(rows, 9), sumOf(rows, 10), sumOf(rows, 11), ""] });
  return bytesOf(wb);
}

export interface EmployeeProfile {
  log: AttendanceLog;
  payroll: PayrollDetails;
  loans: Array<{ status: string; amount: number; remaining: number; installment: number; installments_count: number; cash?: boolean;
    requested_at?: string; installments?: Array<{ due_date: string; amount: number; paid: boolean }> | null }>;
  leaves: { balance?: Record<string, unknown>; requests?: Array<{ type: string; status: string; paid: boolean; hourly: boolean;
    from: string; to: string; hours?: string | null; reason?: string | null }> };
}

const LOAN_STATUS: Record<string, string> = { approved: "معتمدة", pending: "قيد المراجعة", rejected: "مرفوضة" };
const LEAVE_STATUS: Record<string, string> = { approved: "معتمدة", pending: "قيد المراجعة", rejected: "مرفوضة", cancelled: "ملغاة" };

/** ملف شامل لموظف: الدوام + ملخصه + الراتب + السلف + الإجازات. */
export async function buildEmployeeProfileWorkbook(p: EmployeeProfile): Promise<Uint8Array> {
  const wb = newBook();
  const name = p.log.employee.name;
  addAttendanceSummarySheet(wb, p.log, "ملخص الدوام");
  addAttendanceSheet(wb, p.log, "سجل الدوام");
  addPayrollSheet(wb, p.payroll, "الراتب");
  const loanRows = p.loans.flatMap((l) => (l.installments?.length ? l.installments : [null]).map((li, i) => [
    i === 0 ? LOAN_STATUS[l.status] ?? l.status : "", i === 0 ? money(l.amount) : "", i === 0 ? money(l.remaining) : "",
    li?.due_date ?? "", li ? money(li.amount) : "", li ? (li.paid ? "مدفوع" : "باقي") : "", i === 0 && l.cash ? "نقداً" : ""]));
  addTableSheet(wb, "السلف", `سلف ${name}`, `أُصدر: ${issued()}`,
    ["الحالة", "المبلغ", "الباقي", "استحقاق القسط", "القسط", "القسط مدفوع؟", "الدفع"], [14, 13, 13, 14, 12, 13, 10], loanRows,
    { moneyCols: [2, 3, 5] });
  const leaveRows = (p.leaves.requests ?? []).map((r, i) => [i + 1, r.type, LEAVE_STATUS[r.status] ?? r.status, r.paid ? "مدفوعة" : "بدون راتب",
    r.hourly ? `زمنية ${r.hours ?? ""}` : "يومية", r.from, r.to, r.reason ?? ""]);
  const bal = p.leaves.balance as Record<string, Record<string, unknown>> | undefined;
  addTableSheet(wb, "الإجازات", `إجازات ${name}`,
    `الرصيد — اعتيادية: ${bal?.annual?.left ?? "—"} يوم   ·   مرضية: ${bal?.sick?.left ?? "—"} يوم   ·   زمنية هالشهر: ${bal?.hourly?.left_hours ?? "—"} ساعة`,
    ["#", "النوع", "الحالة", "الراتب", "المدة", "من", "إلى", "السبب"], [5, 14, 13, 12, 16, 12, 12, 30], leaveRows);
  return bytesOf(wb);
}

/** اسم ملف آمن (حروف عربية وأرقام فقط). */
export function safeFileName(parts: string[]): string {
  return parts.join("_").replace(/[^\p{L}\p{N}_-]+/gu, "_").replace(/_+/g, "_").slice(0, 90) + ".xlsx";
}
