// المساعد الذكي للأدمن — نقطة الدخول (HTTP). التحقق من الجلسة ودور الأدمن هنا، والباقي:
//   agent.ts (الحلقة) · tools.ts (أدوات القراءة) · excel.ts (الملفات) · gemini.ts (مزوّد الذكاء) · prompt.ts (التعليمات)
//   context.ts (البيانات الجاهزة قبل السؤال + اختيار الموديل) · voice.ts (السؤال بالصوت: يتحول لنص ثم نفس الحلقة)
// الأسرار: GEMINI_API_KEY (إلزامي)، واختياري: GEMINI_FAST_MODEL (الأسئلة العادية)، GEMINI_MODEL (الأسئلة الثقيلة والصوت)،
// GEMINI_THINKING=default. النشر: supabase functions deploy hr-assistant
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { runAgent, type ChatMessage } from "./agent.ts";
import { needsSmartModel, quickContext } from "./context.ts";
import { type Attempt, GeminiError, geminiGenerate, geminiTranscribe, QuotaError } from "./gemini.ts";
import { systemPrompt } from "./prompt.ts";
import { cleanTranscript, transcriptionInstruction, validateAudio } from "./voice.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "content-type": "application/json; charset=utf-8" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST فقط." }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "المساعد غير مفعّل بعد: مفتاح Gemini غير مضاف للسيرفر." }, 503);
  const started = Date.now();

  let history: ChatMessage[];
  let audioRaw: unknown;
  try {
    const body = await req.json();
    history = Array.isArray(body?.messages) ? body.messages : [];
    audioRaw = body?.audio;
  } catch {
    return json({ error: "طلب غير صالح." }, 400);
  }
  if (!history.length && !audioRaw) return json({ error: "اكتب سؤالك." }, 400);

  // عميل بتوكن المستخدم نفسه: كل الدوال تنطبق عليها صلاحياته
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });

  // قياس الوقت (يطلع بسجل الدالة): وين راح وقت السؤال — الذكاء لو القاعدة، وكل محاولة ويا Google
  const timing = { model_ms: 0, model_calls: 0, db_ms: 0, db_calls: 0, attempts: [] as string[] };
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const t = Date.now();
    const { data, error } = await db.rpc(fn, args);
    timing.db_ms += Date.now() - t;
    timing.db_calls++;
    if (error) throw new Error(error.message);
    return data;
  };
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Baghdad" });

  // البيانات الجاهزة تنجاب ويا فحص الجلسة بنفس الوقت (دوال القاعدة نفسها ترفض غير الأدمن، فما يطلع شي لغيره)
  const earlyContext = audioRaw ? null : quickContext(history, { rpc }, today);
  const [{ data: user }, { data: isAdmin }] = await Promise.all([db.auth.getUser(), db.rpc("is_admin")]);
  if (!user?.user) return json({ error: "سجّل الدخول من جديد." }, 401);
  if (isAdmin !== true) return json({ error: "المساعد الذكي لمسؤول النظام (الأدمن) فقط." }, 403);

  // موديلين: السريع (lite) للأسئلة العادية، والأقوى للأسئلة الثقيلة (اقتراح قرارات، تعاميم، مقارنات، «ليش») وللصوت.
  // كل واحد احتياطي للثاني إذا عليه ضغط أو خلص حده أو تأخر.
  const fastModel = Deno.env.get("GEMINI_FAST_MODEL") ?? "gemini-flash-lite-latest";
  const smartModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest";
  const onAttempt = (a: Attempt) => timing.attempts.push(`${a.model}:${a.status}:${a.ms}`);
  // GEMINI_THINKING=default يرجّع تفكير الموديل الكامل (أبطأ). الافتراضي: أقل تفكير (أسرع).
  const fastThinking = Deno.env.get("GEMINI_THINKING") !== "default";
  const smartFirst = { fastThinking, onAttempt, timeoutsMs: [30000, 30000] };
  const fastFirst = { fastThinking, onAttempt, timeoutsMs: [12000, 45000] };

  try {
    // سؤال بالصوت: يتحول لنص (الأسماء بإملاء النظام) ويكمل كأنه مكتوب. الصوت ما ينحفظ.
    let transcript: string | undefined;
    if (audioRaw) {
      const audio = validateAudio(audioRaw);
      if (typeof audio === "string") return json({ error: audio }, 400);
      const hints = await rpc("assistant_name_hints", {}) as { employees?: string[]; branches?: string[] };
      const text = cleanTranscript(
        await geminiTranscribe(apiKey, [smartModel, fastModel], smartFirst)(audio, transcriptionInstruction(hints)));
      if (!text) return json({ error: "ما انفهم التسجيل. احچي بوضوح وقرّب الموبايل، وجرّب مرة ثانية." }, 422);
      transcript = text;
      history = [...history, { role: "user", text }];
    }
    const question = [...history].reverse().find((m) => m?.role === "user")?.text ?? "";
    const smart = needsSmartModel(question);
    const generate = geminiGenerate(apiKey, smart ? [smartModel, fastModel] : [fastModel, smartModel], smart ? smartFirst : fastFirst);
    const context = await (earlyContext ?? quickContext(history, { rpc }, today));
    const reply = await runAgent({
      generate: async (r) => {
        const t = Date.now();
        try {
          return await generate(r);
        } finally {
          timing.model_ms += Date.now() - t;
          timing.model_calls++;
        }
      },
      system: systemPrompt(today) + context,
      history,
      ctx: { rpc },
    });
    console.log("hr-assistant timing", JSON.stringify({ total_ms: Date.now() - started, ...timing, smart, context_chars: context.length, voice: !!audioRaw }));
    return json(transcript ? { ...reply, transcript } : reply);
  } catch (e) {
    console.log("hr-assistant timing (failed)", JSON.stringify({ total_ms: Date.now() - started, ...timing }));
    if (e instanceof QuotaError) {
      return json({ error: "خلص الحد المجاني للمساعد هسه. جرّب بعد شوية (الحد يتجدد كل دقيقة وكل يوم)." }, 429);
    }
    if (e instanceof GeminiError) {
      console.error("hr-assistant", e.message);
      return json({ error: e.arabic }, 502);
    }
    console.error("hr-assistant", e);
    return json({ error: "صار خطأ بالمساعد. جرّب مرة ثانية." }, 500);
  }
});
