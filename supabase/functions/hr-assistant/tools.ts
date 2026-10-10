// أدوات المساعد: كل أداة = دالة قراءة بالقاعدة (supabase/migrations/20261008000000_hr_assistant.sql) تُنادى بتوكن الأدمن
// نفسه، فصلاحيات القاعدة تنطبق. ماكو أي أداة كتابة (القرارات والمسودات بطاقات يأكدها الأدمن بنفسه). أدوات الملفات ترجّع مرفقاً للشاشة، والذكاء يشوف ملخصاً فقط.

import type { AttendanceLog, BranchAttendance, EmployeeProfile, PayrollDetails, PayrollRun } from "./excel.ts";
import type { FunctionDecl } from "./gemini.ts";

/** مكتبة Excel ثقيلة: تتحمل بس لما ينطلب ملف، حتى المساعد يشتغل أسرع ببداية كل تشغيل. */
const excel = () => import("./excel.ts");

export type Attachment =
  | { kind: "file"; name: string; mime: string; base64: string }
  | { kind: "documents"; employee: string; urls: string[] }
  /** اقتراح قرار: ما ينفذ إلا لما الأدمن يضغط «تأكيد» بالشاشة (decide_payroll_event). البيانات من القاعدة. */
  | { kind: "decision"; event_id: string; employee: string; date: string; type: string; minutes: number; amount: number;
      suggest: "deduct" | "excuse"; reason: string }
  /** مسودة تعميم أو رسالة: تُراجع وتُنشر يدوياً من شاشة التعاميم (المساعد ما ينشر شي). */
  | { kind: "draft"; draft_kind: "announcement" | "message"; title: string; body: string };

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
const EMP = p("اسم الموظف (أو جزء منه) أو كوده أو معرّفه (id) — الاسم يكفي، ما تحتاج find_employees قبلها");

interface EmployeeMatch { id: string; name: string; code?: string; branch?: string; active?: boolean }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * معرّف الموظف من الاسم/الكود مباشرة (يوفّر جولة كاملة مع الذكاء). موظف واحد = نكمل؛ أكثر من واحد أو ماكو = نرجع
 * للذكاء حتى يسأل الأدمن. المعرّف (uuid) يمر مثل ما هو.
 */
export async function resolveEmployee(value: unknown, ctx: ToolContext): Promise<{ id: string } | { stop: ToolResult }> {
  const q = String(value ?? "").trim();
  if (!q) return { stop: { forModel: { error: "اكتب اسم الموظف." } } };
  if (UUID.test(q)) return { id: q };
  const found = (await ctx.rpc("assistant_find_employees", { p_query: q, p_branch: null }) ?? []) as EmployeeMatch[];
  if (found.length === 1) return { id: found[0].id };
  if (!found.length) return { stop: { forModel: { error: `ما لكيت موظف باسم «${q}». تأكد من الاسم أو جرّب جزء منه.` } } };
  const exact = found.filter((e) => e.name?.trim() === q);
  if (exact.length === 1) return { id: exact[0].id };
  return {
    stop: {
      forModel: {
        need_choice: true,
        matches: found.map((e) => ({ id: e.id, name: e.name, code: e.code, branch: e.branch, active: e.active })),
        note: "أكثر من موظف بهذا الاسم: اسأل الأدمن يا واحد يقصد (اذكر الفرع والكود)، وبعدها ناد الأداة بالمعرّف id.",
      },
    },
  };
}

/** يلف أداة موظف: يحوّل الاسم لمعرّف أول، ثم يشغّلها. */
const withEmployee = (run: (id: string, a: Record<string, unknown>, ctx: ToolContext) => Promise<ToolResult>) =>
  async (a: Record<string, unknown>, ctx: ToolContext): Promise<ToolResult> => {
    const r = await resolveEmployee(a.employee_id ?? a.employee, ctx);
    return "stop" in r ? r.stop : run(r.id, a, ctx);
  };
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
      description: "يبحث عن موظفين بالاسم (أو جزء منه) أو الكود، واختيارياً باسم الفرع. للبحث بس؛ أدوات الموظف تقبل الاسم مباشرة.",
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
    run: withEmployee(async (id, a, ctx) => {
      const log = await ctx.rpc("assistant_attendance_log", { p_employee_id: id, p_from: a.from, p_to: a.to }) as AttendanceLog;
      return { forModel: compactLog(log) };
    }),
  },
  {
    decl: {
      name: "attendance_excel",
      description: "يسوي ملف Excel احترافي لسجل دوام موظف يوم بيوم (مع القرار: مخصوم/معفى/بانتظار والملاحظة). استعمله إذا طلب ملف/إكسل/تقرير.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, from: DATE("بداية الفترة"), to: DATE("نهاية الفترة") }, required: ["employee_id", "from", "to"] },
    },
    run: withEmployee(async (id, a, ctx) => {
      const [log, { buildAttendanceWorkbook, safeFileName }] = await Promise.all([
        ctx.rpc("assistant_attendance_log", { p_employee_id: id, p_from: a.from, p_to: a.to }) as Promise<AttendanceLog>,
        excel(),
      ]);
      const name = safeFileName(["سجل_دوام", log.employee.name, log.from, log.to]);
      const bytes = await buildAttendanceWorkbook(log);
      return {
        forModel: { file_ready: name, summary: log.summary },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    }),
  },
  {
    decl: {
      name: "payroll_details",
      description: "راتب موظف لشهر مسير (YYYY-MM): الأساسي، الإضافات، الخصومات بالتفصيل (كل حركة بسببها وقرارها)، أقساط السلف، والصافي.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, month: p("شهر المسير YYYY-MM") }, required: ["employee_id", "month"] },
    },
    run: withEmployee(async (id, a, ctx) => ({ forModel: await ctx.rpc("assistant_payroll", { p_employee_id: id, p_month: a.month }) as Record<string, unknown> })),
  },
  {
    decl: {
      name: "payroll_excel",
      description: "يسوي ملف Excel لتفاصيل راتب وخصومات موظف لشهر مسير (YYYY-MM).",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, month: p("شهر المسير YYYY-MM") }, required: ["employee_id", "month"] },
    },
    run: withEmployee(async (id, a, ctx) => {
      const [d, { buildPayrollWorkbook, safeFileName }] = await Promise.all([
        ctx.rpc("assistant_payroll", { p_employee_id: id, p_month: a.month }) as Promise<PayrollDetails>,
        excel(),
      ]);
      const name = safeFileName(["تفاصيل_راتب", d.employee, d.month]);
      const bytes = await buildPayrollWorkbook({ ...d, events: d.events ?? [] });
      return {
        forModel: { file_ready: name, summary: d.summary ?? d.message },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    }),
  },
  {
    decl: {
      name: "employee_documents",
      description: "يعرض وثائق (مستمسكات) موظف على الشاشة للأدمن.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP }, required: ["employee_id"] },
    },
    run: withEmployee(async (id, _a, ctx) => {
      const d = await ctx.rpc("assistant_documents", { p_employee_id: id }) as { employee: string; count: number; urls: string[] };
      return {
        forModel: { employee: d.employee, documents_count: d.count, shown_on_screen: d.count > 0 },
        attachment: d.count > 0 ? { kind: "documents", employee: d.employee, urls: d.urls } : undefined,
      };
    }),
  },
  {
    decl: {
      name: "employee_loans",
      description: "سلف موظف: المبلغ، الباقي، القسط، والأقساط المدفوعة والباقية.",
      parameters: { type: "OBJECT", properties: { employee_id: EMP }, required: ["employee_id"] },
    },
    run: withEmployee(async (id, _a, ctx) => ({ forModel: { loans: await ctx.rpc("assistant_loans", { p_employee_id: id }) } })),
  },
  {
    decl: {
      name: "employee_leaves",
      description: "رصيد إجازات موظف وطلباته (اختياري بفترة).",
      parameters: { type: "OBJECT", properties: { employee_id: EMP, from: DATE("من (اختياري)"), to: DATE("إلى (اختياري)") }, required: ["employee_id"] },
    },
    run: withEmployee(async (id, a, ctx) => ({
      forModel: await ctx.rpc("assistant_leaves", { p_employee_id: id, p_from: str(a.from) ?? null, p_to: str(a.to) ?? null }) as Record<string, unknown>,
    })),
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
      name: "morning_summary",
      description: "ملخص سريع لليوم (نفس إشعار الصباح): كم بصم من المجدولين، المتأخرين، المجازين، منو ما بصم بعد، القرارات المعلّقة، وكم باقي على قطع الرواتب.",
      parameters: { type: "OBJECT", properties: { date: DATE("اليوم (اختياري)") } },
    },
    run: async (a, ctx) => ({ forModel: await ctx.rpc("assistant_morning_summary", { p_date: str(a.date) ?? null }) as Record<string, unknown> }),
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
      const [r, { buildBranchAttendanceWorkbook, safeFileName }] = await Promise.all([
        ctx.rpc("assistant_branch_attendance", { p_branch: str(a.branch) ?? null, p_from: a.from, p_to: a.to }) as Promise<BranchAttendance>,
        excel(),
      ]);
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
      const [run, { buildPayrollRunWorkbook, safeFileName }] = await Promise.all([
        ctx.rpc("assistant_payroll_run", { p_month: a.month }) as Promise<PayrollRun & { totals?: unknown }>,
        excel(),
      ]);
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
      parameters: { type: "OBJECT", properties: { employee_id: p("اسم الموظف أو معرّفه (اختياري)"), branch: p("اسم الفرع (اختياري)"),
        month_a: p("الشهر الأول YYYY-MM"), month_b: p("الشهر الثاني YYYY-MM") }, required: ["month_a", "month_b"] },
    },
    run: async (a, ctx) => {
      let id: string | null = null;
      if (str(a.employee_id)?.trim()) {
        const r = await resolveEmployee(a.employee_id, ctx);
        if ("stop" in r) return r.stop;
        id = r.id;
      }
      return {
        forModel: await ctx.rpc("assistant_compare", { p_employee_id: id, p_branch: str(a.branch) ?? null,
          p_month_a: a.month_a, p_month_b: a.month_b }) as Record<string, unknown>,
      };
    },
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
    run: withEmployee(async (id, a, ctx) => {
      const payroll = await ctx.rpc("assistant_payroll", { p_employee_id: id, p_month: a.month }) as PayrollDetails;
      if (!payroll.period) return { forModel: { error: payroll.message ?? "هذا الشهر ما بيه مسير." } };
      const [log, loans, leaves, { buildEmployeeProfileWorkbook, safeFileName }] = await Promise.all([
        ctx.rpc("assistant_attendance_log", { p_employee_id: id, p_from: payroll.period.from, p_to: payroll.period.to }) as Promise<AttendanceLog>,
        ctx.rpc("assistant_loans", { p_employee_id: id }) as Promise<EmployeeProfile["loans"]>,
        ctx.rpc("assistant_leaves", { p_employee_id: id, p_from: null, p_to: null }) as Promise<EmployeeProfile["leaves"]>,
        excel(),
      ]);
      const name = safeFileName(["ملف_شامل", log.employee.name, payroll.month]);
      const bytes = await buildEmployeeProfileWorkbook({ log, payroll: { ...payroll, events: payroll.events ?? [] }, loans, leaves });
      return {
        forModel: { file_ready: name, attendance: log.summary, payroll: payroll.summary },
        attachment: { kind: "file", name, mime: XLSX, base64: toBase64(bytes) },
      };
    }),
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
  {
    decl: {
      name: "draft_message",
      description: "يعرض للأدمن مسودة تعميم أو رسالة كتبتها انت (عنوان + نص) ببطاقة فيها «نسخ» و«فتح كتعميم». ما ينشر ولا يرسل شي.",
      parameters: {
        type: "OBJECT",
        properties: {
          kind: { type: "STRING", enum: ["announcement", "message"], description: "announcement = تعميم لكل/بعض الموظفين، message = رسالة لموظف" },
          title: p("عنوان قصير"),
          body: p("نص المسودة كامل"),
        },
        required: ["kind", "title", "body"],
      },
    },
    run: async (a) => {
      const title = String(a.title ?? "").trim().slice(0, 120);
      const body = String(a.body ?? "").trim().slice(0, 2000);
      if (!title || !body) return { forModel: { error: "المسودة تحتاج عنوان ونص." } };
      return {
        forModel: { draft_shown: true, note: "المسودة ظهرت للأدمن؛ هو يراجعها وينشرها بنفسه من شاشة التعاميم." },
        attachment: { kind: "draft", draft_kind: a.kind === "message" ? "message" : "announcement", title, body },
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
