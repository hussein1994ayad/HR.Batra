// فحوص المساعد بدون إنترنت ولا قاعدة: ذكاء وهمي + دوال قاعدة وهمية.
// التشغيل: npx deno test --allow-env --allow-read supabase/functions/hr-assistant/
import ExcelJS from "npm:exceljs@4.4.0";
import { assert, assertEquals } from "jsr:@std/assert@1";
import { runAgent, toContents, MAX_HISTORY } from "./agent.ts";
import { buildAttendanceWorkbook, buildPayrollWorkbook, safeFileName, type AttendanceLog } from "./excel.ts";
import type { Content, Generate } from "./gemini.ts";
import { compactLog, runTool } from "./tools.ts";

const LOG: AttendanceLog = {
  employee: { name: "علي محمد سعيد", code: "K7", branch: "كمب سارة" },
  from: "2026-09-27", to: "2026-09-29",
  summary: { present: 1, late: 1, absent: 1, deducted_days: 1, excused_days: 1, late_minutes: 30, deducted_total: 1250 },
  days: [
    { date: "2026-09-27", weekday: 0, status: "متأخر", check_in: "09:30", check_out: "17:00", late_minutes: 30,
      decision: "مخصوم", deducted: 1250, events: [{ type: "late", reason: "بدون عذر" }] },
    { date: "2026-09-28", weekday: 1, status: "غياب", decision: "معفى", deducted: 0,
      events: [{ type: "absence", reason: "نسي البصمة وهو مداوم" }] },
    { date: "2026-09-29", weekday: 2, status: "حاضر", check_in: "08:58", check_out: "17:05" },
  ],
};

const rpc = async (fn: string, _args: Record<string, unknown>) => {
  if (fn === "assistant_find_employees") return [{ id: "e1", name: "علي محمد سعيد", branch: "كمب سارة" }];
  if (fn === "assistant_attendance_log") return LOG;
  if (fn === "assistant_documents") return { employee: "علي محمد سعيد", count: 2, urls: ["u1", "u2"] };
  if (fn === "assistant_payroll") {
    return { employee: "علي محمد سعيد", month: "2026-10", period: { from: "2026-09-27", to: "2026-10-26", status: "open" },
      summary: { basic: 600000, earnings: 0, deductions: 1250, loans: 50000, net: 548750, pending_count: 1 },
      events: [{ date: "2026-09-27", type: "late", minutes: 30, amount: 1250, direction: -1, decision: "محتسب", reason: "بدون عذر" }],
      loan_installments: [{ due_date: "2026-10-01", amount: 50000, paid: false }] };
  }
  throw new Error(`unexpected ${fn}`);
};

/** ذكاء وهمي ينفّذ سيناريو ثابت: يطلب أدوات بالتسلسل ثم يكتب جواباً. */
function scripted(steps: Array<Content["parts"]>): { generate: Generate; seen: Content[][] } {
  const seen: Content[][] = [];
  let i = 0;
  return {
    seen,
    generate: (req) => {
      seen.push(structuredClone(req.contents));
      return Promise.resolve({ role: "model", parts: steps[Math.min(i++, steps.length - 1)] });
    },
  };
}

async function readWorkbook(bytes: Uint8Array) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(bytes.buffer as ArrayBuffer);
  return wb;
}

Deno.test("attendance Excel: RTL, title, colored status and decision, totals, summary sheet", async () => {
  const wb = await readWorkbook(await buildAttendanceWorkbook(LOG));
  const ws = wb.getWorksheet("سجل الدوام")!;
  assert(ws.views[0].rightToLeft);
  assertEquals(String(ws.getCell("A1").value), "سجل دوام — علي محمد سعيد");
  assertEquals(ws.getCell("D5").value, "متأخر");
  assertEquals((ws.getCell("D5").fill as ExcelJS.FillPattern).fgColor?.argb, "FFFEF9C3");
  assertEquals(ws.getCell("J5").value, "مخصوم");
  assertEquals(ws.getCell("K5").value, 1250);
  assertEquals(ws.getCell("J6").value, "معفى");
  assertEquals(ws.getCell("L6").value, "نسي البصمة وهو مداوم");
  assertEquals(ws.getCell("B8").value, "المجموع");
  assertEquals(ws.getCell("K8").value, 1250);
  assert(wb.getWorksheet("الملخص"));
});

Deno.test("payroll Excel: summary block, events with decision, loan installment", async () => {
  const wb = await readWorkbook(await buildPayrollWorkbook((await rpc("assistant_payroll", {})) as never));
  const ws = wb.getWorksheet("تفاصيل الراتب")!;
  assertEquals(ws.getCell("A8").value, "الصافي");
  assertEquals(ws.getCell("B8").value, 548750);
  assertEquals(ws.getCell("C13").value, "تأخير");
  assertEquals(ws.getCell("G13").value, "محتسب");
  assertEquals(ws.getCell("C16").value, 50000);
});

Deno.test("file names are safe", () => {
  assertEquals(safeFileName(["سجل_دوام", "علي / محمد", "2026-09-27"]), "سجل_دوام_علي_محمد_2026-09-27.xlsx");
});

Deno.test("the model sees a compact log: no normal days, no links", () => {
  const c = compactLog(LOG) as { notable_days: Array<{ date: string }> };
  assertEquals(c.notable_days.map((d) => d.date), ["2026-09-27", "2026-09-28"]);
});

Deno.test("agent: find employee → Excel → answer; the file is attached, the model sees only a summary", async () => {
  const { generate, seen } = scripted([
    [{ functionCall: { name: "find_employees", args: { query: "علي محمد سعيد", branch: "كمب سارة" } } }],
    [{ functionCall: { name: "attendance_excel", args: { employee_id: "e1", from: "2026-09-27", to: "2026-09-29" } } }],
    [{ text: "سويتلك ملف سجل الدوام، تلگاه تحت." }],
  ]);
  const reply = await runAgent({ generate, system: "s", history: [{ role: "user", text: "سجل دوام علي" }], ctx: { rpc } });
  assertEquals(reply.text, "سويتلك ملف سجل الدوام، تلگاه تحت.");
  assertEquals(reply.attachments.length, 1);
  const file = reply.attachments[0];
  assert(file.kind === "file" && file.name.endsWith(".xlsx") && file.base64.length > 1000);
  const toModel = JSON.stringify(seen[2]);
  assert(toModel.includes("file_ready") && !toModel.includes(file.kind === "file" ? file.base64.slice(0, 50) : "x"));
});

Deno.test("agent: documents go to the screen, never their links to the model", async () => {
  const { generate, seen } = scripted([
    [{ functionCall: { name: "employee_documents", args: { employee_id: "e1" } } }],
    [{ text: "هاي وثائقه." }],
  ]);
  const reply = await runAgent({ generate, system: "s", history: [{ role: "user", text: "وثائق علي" }], ctx: { rpc } });
  assertEquals(reply.attachments, [{ kind: "documents", employee: "علي محمد سعيد", urls: ["u1", "u2"] }]);
  assert(!JSON.stringify(seen[1]).includes("u1"));
});

Deno.test("agent: tool errors return to the model as text (not a crash)", async () => {
  const r = await runTool("attendance_log", { employee_id: "x", from: "a", to: "b" }, {
    rpc: () => Promise.reject(new Error("الفترة طويلة: أقصاها 3 أشهر بالطلب الواحد.")),
  });
  assertEquals(r.forModel, { error: "الفترة طويلة: أقصاها 3 أشهر بالطلب الواحد." });
});

Deno.test("agent: endless tool calls stop after the round limit", async () => {
  const { generate } = scripted([[{ functionCall: { name: "list_branches" } }]]);
  const reply = await runAgent({ generate, system: "s", history: [{ role: "user", text: "؟" }], ctx: { rpc: () => Promise.resolve([]) } });
  assert(reply.text.includes("خطوات كثيرة"));
});

Deno.test("history: last messages only, text only", () => {
  const many = Array.from({ length: 30 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", text: `m${i}` }) as const);
  const c = toContents([...many, { role: "user", text: "  " }]);
  assertEquals(c.length, MAX_HISTORY);
  assertEquals(c.at(-1)!.parts, [{ text: "m29" }]);
});

// ---------------- المرحلة A: تقارير ----------------
import { buildBranchAttendanceWorkbook, buildEmployeeProfileWorkbook, buildPayrollRunWorkbook } from "./excel.ts";

Deno.test("branch Excel: summary row per employee + a sheet per employee (same names get unique sheets)", async () => {
  const twin = { ...LOG, employee: { ...LOG.employee } };
  const wb = await readWorkbook(await buildBranchAttendanceWorkbook({ scope: "كمب سارة", from: LOG.from, to: LOG.to, employees: [LOG, twin] }));
  const names = wb.worksheets.map((w) => w.name);
  assertEquals(names.length, 3);
  assertEquals(names[0], "الملخص");
  assert(names[1] !== names[2], names.join("|"));
  const sum = wb.getWorksheet("الملخص")!;
  assertEquals(sum.getCell("B5").value, "علي محمد سعيد");
  assertEquals(sum.getCell("L7").value, 2500); // مجموع المخصوم للموظفين
});

Deno.test("payroll run Excel: one row per employee and totals", async () => {
  const wb = await readWorkbook(await buildPayrollRunWorkbook({ month: "2026-10", period: { from: "2026-09-27", to: "2026-10-26", status: "open" },
    rows: [{ employee: "أ", branch: "ف", basic: 600000, earnings: 0, deductions: 1250, loans: 50000, net: 548750, issued: false },
      { employee: "ب", branch: "ف", basic: 900000, earnings: 25000, deductions: 0, loans: 0, net: 925000, issued: true }] }));
  const ws = wb.getWorksheet("رواتب الشهر")!;
  assertEquals(ws.getCell("H7").value, 548750 + 925000);
  assertEquals(ws.getCell("L6").value, "صدر الكشف");
});

Deno.test("employee profile Excel: attendance, payroll, loans, leaves sheets", async () => {
  const payroll = await rpc("assistant_payroll", {}) as never;
  const wb = await readWorkbook(await buildEmployeeProfileWorkbook({
    log: LOG, payroll,
    loans: [{ status: "approved", amount: 300000, remaining: 250000, installment: 50000, installments_count: 6,
      installments: [{ due_date: "2026-09-01", amount: 50000, paid: true }, { due_date: "2026-10-01", amount: 50000, paid: false }] }],
    leaves: { balance: { annual: { left: 10 } }, requests: [{ type: "اعتيادية", status: "approved", paid: true, hourly: false, from: "2026-09-10", to: "2026-09-11" }] },
  }));
  assertEquals(wb.worksheets.map((w) => w.name), ["ملخص الدوام", "سجل الدوام", "الراتب", "السلف", "الإجازات"]);
  assertEquals(wb.getWorksheet("السلف")!.getCell("C5").value, 250000);
});

Deno.test("employee_profile_excel tool: reads the month period then builds one file", async () => {
  const calls: string[] = [];
  const r = await runTool("employee_profile_excel", { employee_id: "e1", month: "2026-10" }, {
    rpc: async (fn, args) => {
      calls.push(fn);
      if (fn === "assistant_loans") return [];
      if (fn === "assistant_leaves") return { balance: {}, requests: [] };
      return rpc(fn, args);
    },
  });
  assertEquals(calls[0], "assistant_payroll");
  assert(calls.includes("assistant_attendance_log"));
  assert(r.attachment?.kind === "file" && r.attachment.name.startsWith("ملف_شامل"));
});

// ---------------- المرحلة B: اقتراح القرارات ----------------
Deno.test("propose_decisions: cards only for events still pending (data from the DB), nothing executed", async () => {
  const called: string[] = [];
  const r = await runTool("propose_decisions", {
    items: [
      { event_id: "ev1", suggest: "excuse", reason: "أول تأخير بالشهر" },
      { event_id: "gone", suggest: "deduct", reason: "متكرر" },
    ],
  }, {
    rpc: (fn, args) => {
      called.push(fn);
      assertEquals(args, { p_ids: ["ev1", "gone"] });
      return Promise.resolve([{ event_id: "ev1", employee: "علي", date: "2026-10-01", type: "late", minutes: 25, amount: 1042 }]);
    },
  });
  assertEquals(called, ["assistant_pending_events"]); // قراءة فقط، ماكو decide
  assertEquals(r.attachments, [{ kind: "decision", event_id: "ev1", employee: "علي", date: "2026-10-01", type: "late", minutes: 25,
    amount: 1042, suggest: "excuse", reason: "أول تأخير بالشهر" }]);
  assertEquals(r.forModel.skipped_not_pending, 1);
});

// ---------------- المرحلة C: الصوت ----------------
import { cleanTranscript, MAX_AUDIO_BASE64, transcriptionInstruction, validateAudio } from "./voice.ts";

Deno.test("voice: audio validation (type, empty, too long)", () => {
  assertEquals(validateAudio({ mime: "audio/WAV", base64: "UklG" }), { mime: "audio/wav", base64: "UklG" });
  assertEquals(validateAudio({ mime: "audio/webm", base64: "x" }), "نوع التسجيل غير مدعوم.");
  assertEquals(validateAudio(null), "التسجيل فارغ. سجّل مرة ثانية.");
  assertEquals(validateAudio({ mime: "audio/wav", base64: "x".repeat(MAX_AUDIO_BASE64 + 1) }), "التسجيل طويل. أقصاه دقيقة وحدة.");
});

Deno.test("voice: transcription instruction keeps Iraqi dialect and system spelling of names", () => {
  const t = transcriptionInstruction({ employees: ["علي محمد سعيد"], branches: ["كمب سارة"] });
  assert(t.includes("اللهجة العراقية") && t.includes("علي محمد سعيد") && t.includes("كمب سارة"));
});

Deno.test("voice: unclear or empty transcripts are rejected, quotes trimmed", () => {
  assertEquals(cleanTranscript("[غير واضح]"), null);
  assertEquals(cleanTranscript("   "), null);
  assertEquals(cleanTranscript("«شكد انخصم من علي هالشهر؟»"), "شكد انخصم من علي هالشهر؟");
});

// ---------------- المرحلة D: الملخص والمسودات ----------------
Deno.test("draft_message: shows a draft card, publishes nothing, rejects empty drafts", async () => {
  const calls: string[] = [];
  const ctx = { rpc: (fn: string) => { calls.push(fn); return Promise.resolve(null); } };
  const r = await runTool("draft_message", { kind: "announcement", title: " دوام العيد ", body: "يكون الدوام يوم الخميس من 9 إلى 1." }, ctx);
  assertEquals(r.attachment, { kind: "draft", draft_kind: "announcement", title: "دوام العيد", body: "يكون الدوام يوم الخميس من 9 إلى 1." });
  assertEquals(calls, []); // ما ينادي القاعدة ولا ينشر
  const empty = await runTool("draft_message", { kind: "message", title: "x", body: "  " }, ctx);
  assertEquals(empty.attachment, undefined);
  assert(String(empty.forModel.error).includes("عنوان ونص"));
});

Deno.test("morning_summary: reads the database summary", async () => {
  const r = await runTool("morning_summary", {}, {
    rpc: (fn, args) => Promise.resolve(fn === "assistant_morning_summary" && args.p_date === null ? { body: "بصموا 5 من 9" } : null),
  });
  assertEquals(r.forModel, { body: "بصموا 5 من 9" });
});

// ---------------- أخطاء Google بالعربي ----------------
import { GeminiError, geminiGenerate } from "./gemini.ts";

Deno.test("gemini errors: Google's reason reaches the admin in Arabic, key never shown", async () => {
  const fake = (status: number, body: unknown) => () => Promise.resolve(new Response(JSON.stringify(body), { status }));
  const gen = geminiGenerate("SECRET-KEY", "gemini-2.5-flash",
    fake(400, { error: { message: "API key not valid. Please pass a valid API key." } }) as unknown as typeof fetch);
  let err: unknown;
  try { await gen({ system: "s", contents: [], tools: [] }); } catch (e) { err = e; }
  assert(err instanceof GeminiError);
  assert(err.arabic.includes("مفتاح Gemini غلط") && err.arabic.includes("رمز 400"));
  assert(!err.arabic.includes("SECRET-KEY"));
  assert(new GeminiError(403, "User location is not supported for the API use.").arabic.includes("موقع السيرفر"));
  assert(new GeminiError(404, "models/x is not found").arabic.includes("غير موجود"));
});
