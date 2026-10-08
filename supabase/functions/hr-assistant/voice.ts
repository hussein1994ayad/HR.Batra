// السؤال بالصوت: التحقق من الملف وتعليمات النسخ. الصوت ما ينحفظ؛ يتحول لنص ويكمل نفس حلقة الأدوات.

import type { AudioInput } from "./gemini.ts";

/** الأنواع اللي يقبلها Gemini (التطبيق والموقع يرسلون WAV). */
const ALLOWED = new Set(["audio/wav", "audio/x-wav", "audio/wave", "audio/mp3", "audio/mpeg", "audio/aac", "audio/ogg", "audio/flac"]);
/** حوالي دقيقة WAV 16kHz mono بعد base64 (~2.6MB) + هامش. */
export const MAX_AUDIO_BASE64 = 3_500_000;

/** يرجّع الصوت إذا صالح، أو رسالة خطأ عربية. */
export function validateAudio(raw: unknown): AudioInput | string {
  const a = raw as Partial<AudioInput> | null;
  if (!a || typeof a.mime !== "string" || typeof a.base64 !== "string" || !a.base64) return "التسجيل فارغ. سجّل مرة ثانية.";
  if (!ALLOWED.has(a.mime.toLowerCase())) return "نوع التسجيل غير مدعوم.";
  if (a.base64.length > MAX_AUDIO_BASE64) return "التسجيل طويل. أقصاه دقيقة وحدة.";
  return { mime: a.mime.toLowerCase(), base64: a.base64 };
}

/** تعليمات النسخ: حرفياً بالعراقي، والأسماء مثل ما مكتوبة بالنظام. */
export function transcriptionInstruction(hints: { employees?: string[]; branches?: string[] }): string {
  const names = (hints.employees ?? []).slice(0, 300).join("، ");
  const branches = (hints.branches ?? []).join("، ");
  return `اكتب بالضبط شنو انقال بهذا التسجيل الصوتي، باللهجة العراقية مثل ما انحچى (لا تترجم للفصحى ولا تصحح الكلام ولا تجاوب عليه).
اكتب الأرقام والتواريخ بالأرقام (مثل 15 و 2026-10-01 إذا انقال تاريخ كامل).
إذا انذكر اسم موظف أو فرع، اكتبه بنفس الإملاء من هالقوائم إذا يطابق:
الموظفون: ${names || "—"}
الفروع: ${branches || "—"}
إذا التسجيل فارغ أو ما بيه كلام واضح، اكتب: [غير واضح]
اكتب النص فقط بدون أي شي ثاني.`;
}

/** النص بعد النسخ: فارغ أو "غير واضح" = ما انفهم. */
export function cleanTranscript(text: string): string | null {
  const t = text.replace(/^["'«]+|["'»]+$/g, "").trim();
  if (!t || t.includes("[غير واضح]")) return null;
  return t.slice(0, 1000);
}
