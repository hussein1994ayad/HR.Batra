// «بيانات جاهزة»: قبل ما نسأل الذكاء نجيب من القاعدة (أجزاء من الثانية) أكثر شي ينسأل عنه — وضع اليوم، والموظف المذكور
// بالسؤال (راتبه، سلفه، إجازاته، دوامه بالمسير الحالي) — ونحطها ويا التعليمات. هيج أغلب الأسئلة تنجاوب برد واحد من الذكاء
// بدل ردّين أو ثلاثة (طلب أداة ← نتيجة ← جواب). الأدوات تبقى موجودة للي ما مغطى هنا (فترات ثانية، ملفات، قرارات...).

import type { ChatMessage } from "./agent.ts";
import type { AttendanceLog } from "./excel.ts";
import { compactLog, type ToolContext } from "./tools.ts";

const MAX_BLOCK = 5000;
const MAX_CANDIDATES = 8;

/** نفس assistant_norm بالقاعدة: توحيد الهمزات والتاء المربوطة والياء، بدون تشكيل. */
export function norm(text: string): string {
  return (text ?? "").toLowerCase()
    .replace(/[أإآٱ]/g, "ا").replace(/ة/g, "ه").replace(/[ىئ]/g, "ي").replace(/ؤ/g, "و")
    .replace(/[ً-ْـ]/g, "").replace(/[^\p{L}\p{N}\s]/gu, " ").replace(/\s+/g, " ").trim();
}

/** كلمات شائعة تشبه أسماء بعد التوحيد («على» تصير «علي») — ما تنحسب اسم. */
const NOT_NAMES = new Set(["على", "الى", "إلى", "صباح", "مساء", "سلام", "نور", "عيد"]);

/**
 * الموظفين المذكورين بالنص: نطابق كلمات الاسم بالتسلسل من أوله (أحمد ← أحمد علي ← أحمد علي جاسم)، والأطول مطابقة يفوز.
 * يرجع كل الأسماء اللي بنفس أحسن مطابقة (واحد = عرفناه، أكثر = يحتاج الأدمن يختار).
 */
export function mentionedEmployees(text: string, names: string[]): string[] {
  const words = (text ?? "").split(/\s+/).filter((w) => w && !NOT_NAMES.has(w.replace(/[^\p{L}]/gu, "")));
  const tokens = norm(words.join(" ")).split(" ").filter(Boolean);
  if (!tokens.length) return [];
  // حرف جر ملتصق (لأحمد، وأحمد، بأحمد) ينحسب مطابقة لأول كلمة بالاسم
  const same = (token: string, part: string, first: boolean) =>
    token === part || (first && token.length > part.length && /^[ولبف]$/.test(token.slice(0, token.length - part.length)) && token.endsWith(part));
  let best = 0;
  const scored: Array<[string, number]> = [];
  for (const name of names) {
    const parts = norm(name).split(" ").filter(Boolean);
    if (!parts.length) continue;
    let score = 0;
    for (let i = 0; i < tokens.length; i++) {
      let k = 0;
      while (k < parts.length && i + k < tokens.length && same(tokens[i + k], parts[k], k === 0)) k++;
      if (k > score) score = k;
    }
    if (score > 0) scored.push([name, score]);
    if (score > best) best = score;
  }
  return scored.filter(([, sc]) => sc === best).map(([n]) => n);
}

/** مسير الرواتب الحالي (YYYY-MM): بعد يوم القطع = الشهر الجاي (نفس payroll_month_of). */
export function currentPayrollMonth(today: string, cutoffDay = 26): string {
  const [y, m, d] = today.split("-").map(Number);
  if (d <= cutoffDay) return `${y}-${String(m).padStart(2, "0")}`;
  return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, "0")}`;
}

const block = (title: string, data: unknown): string => {
  const text = JSON.stringify(data);
  if (!text || text === "null" || text === "{}" || text === "[]") return "";
  return `- ${title}: ${text.length > MAX_BLOCK ? `${text.slice(0, MAX_BLOCK)}…(مقطوع: للتفاصيل الكاملة استعمل الأداة)` : text}`;
};

interface Match { id: string; name: string; code?: string; branch?: string; active?: boolean }

/** نص «البيانات الجاهزة» للسؤال الأخير. أي فشل هنا ما يوكف المساعد: يرجع اللي انجاب بس. */
export async function quickContext(history: ChatMessage[], ctx: ToolContext, today: string): Promise<string> {
  const safe = <T>(p: Promise<T>): Promise<T | null> => p.catch(() => null);
  const userTexts = history.filter((m) => m?.role === "user" && typeof m.text === "string").map((m) => m.text).reverse();
  if (!userTexts.length) return "";

  const [hints, overview, summary] = await Promise.all([
    safe(ctx.rpc("assistant_name_hints", {}) as Promise<{ employees?: string[] }>),
    safe(ctx.rpc("assistant_day_overview", { p_date: null, p_branch: null })),
    safe(ctx.rpc("assistant_morning_summary", { p_date: null })),
  ]);
  const lines = [block("وضع اليوم لكل فرع (day_overview)", overview), block("ملخص اليوم (morning_summary)", summary)];

  // الموظف: من آخر سؤال، وإذا ما بيه اسم فمن الأسئلة اللي قبله («وسلفه؟»)
  const names = hints?.employees ?? [];
  let mentioned: string[] = [];
  for (const text of userTexts.slice(0, 3)) {
    mentioned = mentionedEmployees(text, names);
    if (mentioned.length) break;
  }
  if (mentioned.length) {
    const first = norm(mentioned[0]).split(" ")[0];
    const found = (await safe(ctx.rpc("assistant_find_employees", { p_query: mentioned.length === 1 ? mentioned[0] : first, p_branch: null }) as Promise<Match[]>)) ?? [];
    const matches = found.filter((e) => mentioned.includes(e.name));
    if (matches.length === 1) {
      const emp = matches[0];
      const month = currentPayrollMonth(today);
      const [payroll, loans, leaves] = await Promise.all([
        safe(ctx.rpc("assistant_payroll", { p_employee_id: emp.id, p_month: month }) as Promise<{ period?: { from: string; to: string } }>),
        safe(ctx.rpc("assistant_loans", { p_employee_id: emp.id })),
        safe(ctx.rpc("assistant_leaves", { p_employee_id: emp.id, p_from: null, p_to: null })),
      ]);
      const log = payroll?.period
        ? await safe(ctx.rpc("assistant_attendance_log", { p_employee_id: emp.id, p_from: payroll.period.from, p_to: payroll.period.to }) as Promise<AttendanceLog>)
        : null;
      lines.push(
        block("الموظف المذكور بالسؤال", { id: emp.id, name: emp.name, code: emp.code, branch: emp.branch, active: emp.active }),
        block(`راتبه لمسير ${month} (payroll_details)`, payroll),
        block("سلفه (employee_loans)", loans),
        block("إجازاته ورصيده (employee_leaves)", leaves),
        log ? block(`دوامه بمسير ${month} (attendance_log)`, compactLog(log)) : "",
      );
    } else if (matches.length > 1) {
      lines.push(block("أكثر من موظف يطابق الاسم بالسؤال — اسأل الأدمن يا واحد يقصد (اذكر الفرع والكود)",
        matches.slice(0, MAX_CANDIDATES).map((e) => ({ id: e.id, name: e.name, code: e.code, branch: e.branch }))));
    }
  }

  const body = lines.filter(Boolean).join("\n");
  return body ? `\n\nبيانات جاهزة (انجابت هسه من القاعدة — إذا تكفي للجواب جاوب منها مباشرة بدون أدوات؛ لغيرها أو لفترة ثانية أو لملف استعمل الأدوات):\n${body}` : "";
}

/**
 * الأسئلة اللي تحتاج الموديل الأقوى (أبطأ شوية): اقتراح قرارات، كتابة تعميم/رسالة، مقارنة وتحليل، و«ليش».
 * الباقي (منو غايب، راتب فلان، سلفه...) قراءة بيانات يكفيها الموديل السريع.
 */
export function needsSmartModel(question: string): boolean {
  return /(اقترح|قرار|تعميم|مسوده|رساله|قارن|مقارنه|حلل|تحليل|ليش|لماذا|انصح|نصيح)/.test(norm(question));
}
