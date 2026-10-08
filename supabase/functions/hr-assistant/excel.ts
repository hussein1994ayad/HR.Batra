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

/** سجل دوام موظف يوم بيوم + ورقة ملخص. */
export async function buildAttendanceWorkbook(log: AttendanceLog): Promise<Uint8Array> {
  const wb = new ExcelJS.Workbook();
  wb.creator = "HR Pro";
  const headers = ["#", "التاريخ", "اليوم", "الحالة", "الحضور", "الانصراف", "تأخير (د)", "خروج مبكر (د)",
    "إجازة / عطلة", "القرار", "المخصوم (د.ع)", "الملاحظة"];
  const ws = newSheet(wb, "سجل الدوام", [5, 12, 11, 14, 10, 10, 10, 12, 20, 15, 14, 34]);
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

  // سطر المجموع
  const s = log.summary;
  const total = ws.getRow(5 + log.days.length);
  total.values = ["", "المجموع", "", "", "", "", Number(s.late_minutes ?? 0), "", "", "", money(s.deducted_total), ""];
  total.eachCell({ includeEmpty: true }, (c) => {
    bodyCell(c, false);
    c.font = { name: "Arial", size: 10, bold: true, color: { argb: "FF" + C.white } };
    c.fill = fill(C.title);
  });
  total.getCell(11).numFmt = "#,##0";

  ws.views = [{ rightToLeft: true, showGridLines: false, state: "frozen", ySplit: 4 }];
  ws.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4 + log.days.length, column: headers.length } };

  const sum = newSheet(wb, "الملخص", [28, 18]);
  titleRows(sum, 2, `ملخص الدوام — ${e.name}`, `${log.from} ← ${log.to}`);
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
  return new Uint8Array(await wb.xlsx.writeBuffer());
}

/** تفاصيل راتب شهر: الملخص + كل حركة بسببها وقرارها + أقساط السلف. */
export async function buildPayrollWorkbook(p: PayrollDetails): Promise<Uint8Array> {
  const wb = new ExcelJS.Workbook();
  wb.creator = "HR Pro";
  const headers = ["#", "التاريخ", "النوع", "المدة", "المبلغ (د.ع)", "خصم / إضافة", "القرار", "الملاحظة", "مرحّل من"];
  const ws = newSheet(wb, "تفاصيل الراتب", [5, 12, 16, 12, 14, 12, 15, 34, 11]);
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
  return new Uint8Array(await wb.xlsx.writeBuffer());
}

/** اسم ملف آمن (حروف عربية وأرقام فقط). */
export function safeFileName(parts: string[]): string {
  return parts.join("_").replace(/[^\p{L}\p{N}_-]+/gu, "_").replace(/_+/g, "_").slice(0, 90) + ".xlsx";
}
