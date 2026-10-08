// أدوات المساعد: كل أداة = دالة قراءة بالقاعدة (supabase/migrations/20261008000000_hr_assistant.sql) تُنادى بتوكن الأدمن
// نفسه، فصلاحيات القاعدة تنطبق. ماكو أي أداة كتابة. أدوات الملفات ترجّع مرفقاً للشاشة، والذكاء يشوف ملخصاً فقط.

import {
  buildAttendanceWorkbook, buildBranchAttendanceWorkbook, buildEmployeeProfileWorkbook, buildPayrollRunWorkbook, buildPayrollWorkbook,
  safeFileName, type AttendanceLog, type BranchAttendance, type EmployeeProfile, type PayrollDetails, type PayrollRun,
} from "./excel.ts";
import type { FunctionDecl } from "./gemini.ts";

export type Attachment =
  | { kind: "file"; name: string; mime: string; base64: string }
  | { kind: "documents"; employee: string; urls: string[] }
  /** اقتراح قرار: ما ينفذ إلا لما الأدمن يضغط «تأكيد» بالشاشة (decide_payroll_event). البيانات من القاعدة. */
  | { kind: "decision"; event_id: string; employee: string; date: string; type: string; minutes: number; amount: number;
      suggest: "deduct" | "excuse"; reason: string };

export interface ToolContext {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<unknown>;
}

export interface ToolResult {
  /** ما يشوفه الذكاء (مختصر، بدون روابط). */
  forModel: Record<string, unknown>;
  attachment?: Attachment;
  /** أكثر من مرفق (مثل بطاقات القرارات). */
  attachments?: Attachment[];
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
  // ---------------- تقارير وتحليلات ----------------
  {
    decl: {
      name: "branch_attendance_excel",
      description: "ملف Excel لسجل دوام فرع كامل أو كل الشركة (بدون فرع): ورقة ملخص بصف لكل موظف + ورقة لكل موظف. الفترة أقصاها 31 يوم.",
      parameters: { type: "OBJECT", properties: { branch: p("اسم الفرع (فارغ = كل الشركة)"), from: DATE("بداية الفترة"), to: DATE("نهاية الفترة") }, required: ["from", "to"] },
    },
    run: async (a, ctx) => {
      const r = await ctx.rpc("assistant_branch_attendance", { p_branch: str(a.branch) ?? null, p_from: a.from, p_to: a.to }) as BranchAttendance;
      const name = safeFileName(["سجل_دوام", r.scope, r.from, r.to]);
      return {
        forModel: { file_ready: name, scope: r.scope, employees: r.employees.map((l) => ({ name: l.employee.name, summary: l.summary })) },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(await buildBranchAttendanceWorkbook(r)) },
      };
    },
  },
  {
    decl: {
      name: "payroll_run",
      description: "رواتب كل الموظفين لشهر مسير (YYYY-MM): الأساسي، الإضافات، الخصومات، السلف، الصافي، وهل صدر الكشف + المجاميع.",
      parameters: { type: "OBJECT", properties: { month: p("شهر المسير YYYY-MM") }, required: ["month"] },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_payroll_run", { p_month: a.month }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "payroll_run_excel",
      description: "ملف Excel لرواتب كل الموظفين لشهر مسير (YYYY-MM) مع المجموع.",
      parameters: { type: "OBJECT", properties: { month: p("شهر المسير YYYY-MM") }, required: ["month"] },
    },
    run: async (a, ctx) => {
      const run = await ctx.rpc("assistant_payroll_run", { p_month: a.month }) as PayrollRun & { totals?: unknown };
      const name = safeFileName(["رواتب", run.month]);
      return {
        forModel: { file_ready: name, totals: run.totals ?? run.message },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(await buildPayrollRunWorkbook({ ...run, rows: run.rows ?? [] })) },
      };
    },
  },
  {
    decl: {
      name: "payroll_readiness",
      description: "شنو باقي قبل اعتماد رواتب شهر (YYYY-MM): القرارات المعلّقة، الموظفين بلا كشف، الصافي بالسالب، البيانات الناقصة، السلف المستحقة، وهل خلصت الفترة.",
      parameters: { type: "OBJECT", properties: { month: p("شهر المسير YYYY-MM") }, required: ["month"] },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_payroll_readiness", { p_month: a.month }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "alerts",
      description: "تنبيهات وأنماط بفترة (أقصاها 3 أشهر): تأخير متكرر بنفس يوم الأسبوع، بصمات ناقصة متكررة، بصمات بدون إنترنت كثيرة، رصيد إجازات قارب يخلص، بيانات ناقصة.",
      parameters: { type: "OBJECT", properties: { from: DATE("من"), to: DATE("إلى") }, required: ["from", "to"] },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_alerts", { p_from: a.from, p_to: a.to }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "compare_months",
      description: "مقارنة شهرين مسير (YYYY-MM) لموظف (employee_id) أو لفرع (branch) أو لكل الشركة: الحضور، التأخير، الغياب، الخروج المبكر، المخصوم.",
      parameters: { type: "OBJECT", properties: { employee_id: p("معرّف الموظف (اختياري)"), branch: p("اسم الفرع (اختياري)"),
        month_a: p("الشهر الأول YYYY-MM"), month_b: p("الشهر الثاني YYYY-MM") }, required: ["month_a", "month_b"] },
    },
    run: async (a, ctx) => ({
      forModel: await ctx.rpc("assistant_compare", { p_employee_id: str(a.employee_id) ?? null, p_branch: str(a.branch) ?? null,
        p_month_a: a.month_a, p_month_b: a.month_b }) as Record<string, unknown>,
    }),
  },
  {
    decl: {
      name: "branch_ranking",
      description: "ترتيب الفروع بالانضباط بفترة (نسبة الحضور، دقائق التأخير لكل موظف، الغياب) + الموظفين الأكثر انضباطاً للتكريم.",
      parameters: { type: "OBJECT", properties: { from: DATE("من"), to: DATE("إلى") }, required: ["from", "to"] },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_branch_ranking", { p_from: a.from, p_to: a.to }) as Record<string, unknown> }),
  },
  {
    decl: {
      name: "employee_profile_excel",
      description: "ملف Excel شامل لموظف لشهر مسير (YYYY-MM): ملخص الدوام، سجل الدوام يوم بيوم، الراتب بالتفصيل، السلف، والإجازات.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, month: p("شهر المسير YYYY-MM") }, required: ["employee_id", "month"] },
    },
    run: async (a, ctx) => {
      const payroll = await ctx.rpc("assistant_payroll", { p_employee_id: a.employee_id, p_month: a.month }) as PayrollDetails;
      if (!payroll.period) return { forModel: { error: payroll.message ?? "هذا الشهر ما بيه مسير." } };
      const [log, loans, leaves] = await Promise.all([
        ctx.rpc("assistant_attendance_log", { p_employee_id: a.employee_id, p_from: payroll.period.from, p_to: payroll.period.to }),
        ctx.rpc("assistant_loans", { p_employee_id: a.employee_id }),
        ctx.rpc("assistant_leaves", { p_employee_id: a.employee_id, p_from: null, p_to: null }),
      ]) as [AttendanceLog, EmployeeProfile["loans"], EmployeeProfile["leaves"]];
      const name = safeFileName(["ملف_شامل", log.employee.name, payroll.month]);
      const bytes = await buildEmployeeProfileWorkbook({ log, payroll: { ...payroll, events: payroll.events ?? [] }, loans, leaves });
      return {
        forModel: { file_ready: name, attendance: log.summary, payroll: payroll.summary },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    },
  },
  // ---------------- اقتراح القرارات (التنفيذ بيد الأدمن) ----------------
  {
    decl: {
      name: "decision_context",
      description: "القرارات المعلّقة (غياب/تأخير/خروج مبكر/بصمة ناقصة) مع سياق كل موظف: كم مرة تكرر بالشهر، كم مرة انخصم أو انعفى خلال 90 يوم، وهل قدّم طلب إجازة لذاك اليوم. استعمله قبل propose_decisions.",
      parameters: { type: "OBJECT", properties: { branch: p("اسم الفرع (اختياري)") } },
    },
    run: async (a, ctx) => ({ forModel: { pending: await ctx.rpc("assistant_decision_context", { p_branch: str(a.branch) ?? null }) } }),
  },
  {
    decl: {
      name: "propose_decisions",
      description: "يعرض للأدمن بطاقات اقتراح (خصم أو إعفاء) لقرارات معلّقة مع سبب قصير. ما ينفذ أي شي: الأدمن يأكد بنفسه من البطاقة.",
      parameters: {
        type: "OBJECT",
        properties: {
          items: {
            type: "ARRAY",
            description: "الاقتراحات",
            items: {
              type: "OBJECT",
              properties: {
                event_id: p("معرّف الحركة من decision_context"),
                suggest: { type: "STRING", enum: ["deduct", "excuse"], description: "deduct = خصم، excuse = إعفاء" },
                reason: p("سبب الاقتراح بجملة قصيرة بالعراقي"),
              },
              required: ["event_id", "suggest", "reason"],
            },
          },
        },
        required: ["items"],
      },
    },
    run: async (a, ctx) => {
      const items = (Array.isArray(a.items) ? a.items : []) as Array<{ event_id?: string; suggest?: string; reason?: string }>;
      const ids = items.map((i) => String(i.event_id ?? "")).filter(Boolean).slice(0, 20);
      const events = (ids.length ? await ctx.rpc("assistant_pending_events", { p_ids: ids }) : []) as Array<
        { event_id: string; employee: string; date: string; type: string; minutes: number; amount: number }>;
      const attachments: Attachment[] = [];
      for (const ev of events) {
        const it = items.find((i) => i.event_id === ev.event_id)!;
        attachments.push({ kind: "decision", ...ev, minutes: Number(ev.minutes ?? 0), amount: Number(ev.amount ?? 0),
          suggest: it.suggest === "deduct" ? "deduct" : "excuse", reason: String(it.reason ?? "").slice(0, 200) });
      }
      const skipped = ids.filter((id) => !events.some((e) => e.event_id === id));
      return {
        forModel: { cards_shown: attachments.length, skipped_not_pending: skipped.length,
          note: "البطاقات ظهرت للأدمن؛ القرار ما ينفذ إلا لما هو يأكد." },
        attachments,
      };
    },
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
