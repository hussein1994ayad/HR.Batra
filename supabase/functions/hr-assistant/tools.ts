// أدوات المساعد: كل أداة = دالة قراءة بالقاعدة (supabase/migrations/20261008000000_hr_assistant.sql) تُنادى بتوكن الأدمن
// نفسه، فصلاحيات القاعدة تنطبق. ماكو أي أداة كتابة. أدوات الملفات ترجّع مرفقاً للشاشة، والذكاء يشوف ملخصاً فقط.

import { buildAttendanceWorkbook, buildPayrollWorkbook, safeFileName, type AttendanceLog, type PayrollDetails } from "./excel.ts";
import type { FunctionDecl } from "./gemini.ts";

export type Attachment =
  | { kind: "file"; name: string; mime: string; base64: string }
  | { kind: "documents"; employee: string; urls: string[] };

export interface ToolContext {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<unknown>;
}

export interface ToolResult {
  /** ما يشوفه الذكاء (مختصر، بدون روابط). */
  forModel: Record<string, unknown>;
  attachment?: Attachment;
}

interface Tool {
  decl: FunctionDecl;
  run: (args: Record<string, unknown>, ctx: ToolContext) => Promise<ToolResult>;
}

const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const str = (v: unknown) => (v == null ? undefined : String(v));
const p = (description: string, type = "STRING") => ({ type, description });
const EMP = p("معرّف الموظف (id) من find_employees");
const DATE = (what: string) => p(`${what} بصيغة YYYY-MM-DD`);

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

/** نسخة مختصرة من السجل للذكاء: الملخص + الأيام غير العادية فقط (توفير وخصوصية). */
export function compactLog(log: AttendanceLog): Record<string, unknown> {
  const notable = log.days
    .filter((d) => !["حاضر", "عطلة أسبوعية", "لم يحن بعد", "خارج فترة الخدمة"].includes(d.status) || d.decision)
    .map((d) => ({
      date: d.date, status: d.status, decision: d.decision ?? undefined, deducted: Number(d.deducted ?? 0) || undefined,
      late_minutes: Number(d.late_minutes ?? 0) || undefined, early_minutes: Number(d.early_minutes ?? 0) || undefined,
      leave: d.leave ?? d.holiday ?? undefined,
      note: (d.events ?? []).map((e) => e.reason).filter(Boolean).join(" · ") || undefined,
    }));
  return { employee: log.employee, from: log.from, to: log.to, summary: log.summary, notable_days: notable };
}

export const TOOLS: Tool[] = [
  {
    decl: {
      name: "find_employees",
      description: "يبحث عن موظف بالاسم (أو جزء منه) أو الكود، واختيارياً باسم الفرع. استعمله دائماً قبل أي أداة تحتاج معرّف موظف.",
      parameters: { type: "OBJECT", properties: { query: p("الاسم أو الكود"), branch: p("اسم الفرع (اختياري)") }, required: ["query"] },
    },
    run: async (a, ctx) => ({ forModel: { results: await ctx.rpc("assistant_find_employees", { p_query: str(a.query), p_branch: str(a.branch) ?? null }) } }),
  },
  {
    decl: { name: "list_branches", description: "أسماء الفروع وعدد موظفي كل فرع." },
    run: async (_a, ctx) => ({ forModel: { branches: await ctx.rpc("assistant_branches", {}) } }),
  },
  {
    decl: {
      name: "attendance_log",
      description: "سجل دوام موظف لفترة (أقصاها 3 أشهر): الغيابات، التأخيرات، الخروج المبكر، الإجازات، وهل انخصم أو انعفى. للإجابة بالكلام.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, from: DATE("بداية الفترة"), to: DATE("نهاية الفترة") }, required: ["employee_id", "from", "to"] },
    },
    run: async (a, ctx) => {
      const log = await ctx.rpc("assistant_attendance_log", { p_employee_id: a.employee_id, p_from: a.from, p_to: a.to }) as AttendanceLog;
      return { forModel: compactLog(log) };
    },
  },
  {
    decl: {
      name: "attendance_excel",
      description: "يسوي ملف Excel احترافي لسجل دوام موظف يوم بيوم (مع القرار: مخصوم/معفى/بانتظار والملاحظة). استعمله إذا طلب ملف/إكسل/تقرير.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, from: DATE("بداية الفترة"), to: DATE("نهاية الفترة") }, required: ["employee_id", "from", "to"] },
    },
    run: async (a, ctx) => {
      const log = await ctx.rpc("assistant_attendance_log", { p_employee_id: a.employee_id, p_from: a.from, p_to: a.to }) as AttendanceLog;
      const name = safeFileName(["سجل_دوام", log.employee.name, log.from, log.to]);
      const bytes = await buildAttendanceWorkbook(log);
      return {
        forModel: { file_ready: name, summary: log.summary },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    },
  },
  {
    decl: {
      name: "payroll_details",
      description: "راتب موظف لشهر مسير (YYYY-MM): الأساسي، الإضافات، الخصومات بالتفصيل (كل حركة بسببها وقرارها)، أقساط السلف، والصافي.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, month: p("شهر المسير YYYY-MM") }, required: ["employee_id", "month"] },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_payroll", { p_employee_id: a.employee_id, p_month: a.month }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "payroll_excel",
      description: "يسوي ملف Excel لتفاصيل راتب وخصومات موظف لشهر مسير (YYYY-MM).",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, month: p("شهر المسير YYYY-MM") }, required: ["employee_id", "month"] },
    },
    run: async (a, ctx) => {
      const d = await ctx.rpc("assistant_payroll", { p_employee_id: a.employee_id, p_month: a.month }) as PayrollDetails;
      const name = safeFileName(["تفاصيل_راتب", d.employee, d.month]);
      const bytes = await buildPayrollWorkbook({ ...d, events: d.events ?? [] });
      return {
        forModel: { file_ready: name, summary: d.summary ?? d.message },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    },
  },
  {
    decl: {
      name: "employee_documents",
      description: "يعرض وثائق (مستمسكات) موظف على الشاشة للأدمن.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP }, required: ["employee_id"] },
    },
    run: async (a, ctx) => {
      const d = await ctx.rpc("assistant_documents", { p_employee_id: a.employee_id }) as { employee: string; count: number; urls: string[] };
      return {
        forModel: { employee: d.employee, documents_count: d.count, shown_on_screen: d.count > 0 },
        attachment: d.count > 0 ? { kind: "documents", employee: d.employee, urls: d.urls } : undefined,
      };
    },
  },
  {
    decl: {
      name: "employee_loans",
      description: "سلف موظف: المبلغ، الباقي، القسط، والأقساط المدفوعة والباقية.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP }, required: ["employee_id"] },
    },
    run: async (a, ctx) => ({ forModel: { loans: await ctx.rpc("assistant_loans", { p_employee_id: a.employee_id }) } }),
  },
  {
    decl: {
      name: "employee_leaves",
      description: "رصيد إجازات موظف وطلباته (اختياري بفترة).",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, from: DATE("من (اختياري)"), to: DATE("إلى (اختياري)") }, required: ["employee_id"] },
    },
    run: async (a, ctx) => ({
      forModel: await ctx.rpc("assistant_leaves", { p_employee_id: a.employee_id, p_from: str(a.from) ?? null, p_to: str(a.to) ?? null }) as Record<string, unknown>,
    }),
  },
  {
    decl: {
      name: "day_overview",
      description: "ملخص يوم لكل فرع: الحاضرين، المتأخرين، المجازين، والغايبين بأسمائهم. بدون تاريخ = اليوم.",
      parameters: { type: "OBJECT", properties: { date: DATE("اليوم (اختياري)"), branch: p("اسم الفرع (اختياري)") } },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_day_overview", { p_date: str(a.date) ?? null, p_branch: str(a.branch) ?? null }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "pending_decisions",
      description: "الغيابات والتأخيرات والخروج المبكر والبصمات الناقصة اللي تنتظر قرار الإدارة (خصم أو إعفاء).",
      parameters: { type: "OBJECT", properties: { branch: p("اسم الفرع (اختياري)") } },
    },
    run: async (a, ctx) => ({ forModel: { pending: await ctx.rpc("assistant_pending_decisions", { p_branch: str(a.branch) ?? null }) } }),
  },
  {
    decl: {
      name: "top_late",
      description: "أكثر الموظفين تأخيراً بفترة (دقائق، أيام، والمخصوم).",
      parameters: { type: "OBJECT", properties: { from: DATE("من"), to: DATE("إلى"), branch: p("اسم الفرع (اختياري)") }, required: ["from", "to"] },
    },
    run: async (a, ctx) => ({ forModel: { ranking: await ctx.rpc("assistant_top_late", { p_from: a.from, p_to: a.to, p_branch: str(a.branch) ?? null }) } }),
  },
];

export const TOOL_DECLS: FunctionDecl[] = TOOLS.map((t) => t.decl);

/** ينفّذ أداة بالاسم؛ الخطأ (مثل فترة طويلة أو موظف غير موجود) يرجع للذكاء كنص حتى يشرحه للأدمن. */
export async function runTool(name: string, args: Record<string, unknown>, ctx: ToolContext): Promise<ToolResult> {
  const tool = TOOLS.find((t) => t.decl.name === name);
  if (!tool) return { forModel: { error: `أداة غير معروفة: ${name}` } };
  try {
    return await tool.run(args ?? {}, ctx);
  } catch (e) {
    return { forModel: { error: e instanceof Error ? e.message : String(e) } };
  }
}
