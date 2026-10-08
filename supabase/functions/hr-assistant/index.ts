// المساعد الذكي للأدمن — نقطة الدخول (HTTP). التحقق من الجلسة ودور الأدمن هنا، والباقي:
//   agent.ts (الحلقة) · tools.ts (أدوات القراءة) · excel.ts (الملفات) · gemini.ts (مزوّد الذكاء) · prompt.ts (التعليمات)
//   voice.ts (السؤال بالصوت: يتحول لنص ثم نفس الحلقة)
// الأسرار: GEMINI_API_KEY (إلزامي)، GEMINI_MODEL و GEMINI_FALLBACK_MODEL (اختياري). النشر: supabase functions deploy hr-assistant
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { runAgent, type ChatMessage } from "./agent.ts";
import { GeminiError, geminiGenerate, geminiTranscribe, QuotaError } from "./gemini.ts";
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

  // عميل بتوكن المستخدم نفسه: كل الدوال تنطبق عليها صلاحياته
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: user } = await db.auth.getUser();
  if (!user?.user) return json({ error: "سجّل الدخول من جديد." }, 401);
  const { data: isAdmin } = await db.rpc("is_admin");
  if (isAdmin !== true) return json({ error: "المساعد الذكي لمسؤول النظام (الأدمن) فقط." }, 403);

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

  // اسم ثابت من Google يأشّر دائماً على أحدث Flash (الموديلات القديمة تتوقف للمستخدمين الجدد). للتثبيت: سر GEMINI_MODEL.
  const models = [
    Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest",
    // احتياطي لما الأساسي عليه ضغط أو خلص حده المجاني (حد منفصل)
    Deno.env.get("GEMINI_FALLBACK_MODEL") ?? "gemini-flash-lite-latest",
  ];
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) throw new Error(error.message);
    return data;
  };
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Baghdad" });
  try {
    // سؤال بالصوت: يتحول لنص (الأسماء بإملاء النظام) ويكمل كأنه مكتوب. الصوت ما ينحفظ.
    let transcript: string | undefined;
    if (audioRaw) {
      const audio = validateAudio(audioRaw);
      if (typeof audio === "string") return json({ error: audio }, 400);
      const hints = await rpc("assistant_name_hints", {}) as { employees?: string[]; branches?: string[] };
      const text = cleanTranscript(await geminiTranscribe(apiKey, models)(audio, transcriptionInstruction(hints)));
      if (!text) return json({ error: "ما انفهم التسجيل. احچي بوضوح وقرّب الموبايل، وجرّب مرة ثانية." }, 422);
      transcript = text;
      history = [...history, { role: "user", text }];
    }
    const reply = await runAgent({
      generate: geminiGenerate(apiKey, models),
      system: systemPrompt(today),
      history,
      ctx: { rpc },
    });
    return json(transcript ? { ...reply, transcript } : reply);
  } catch (e) {
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
