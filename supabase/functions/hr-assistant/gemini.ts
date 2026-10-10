// مزوّد الذكاء (Google Gemini) — كل ما يخص المزوّد بهذا الملف فقط. التبديل لمزوّد ثاني = استبدال هذا الملف
// بنفس الواجهة (generate). REST مباشر بدون SDK حتى تبقى الدالة خفيفة.

export type Part =
  | { text: string; thought?: boolean }
  | { functionCall: { name: string; args?: Record<string, unknown> }; thoughtSignature?: string }
  | { functionResponse: { name: string; response: Record<string, unknown> } };

export interface Content {
  role: "user" | "model";
  parts: Part[];
}

/** مخطط مدخلات الأداة (نفس OpenAPI المختصر اللي يفهمه Gemini). */
export interface Schema {
  type: string;
  description?: string;
  enum?: string[];
  items?: Schema;
  properties?: Record<string, Schema>;
  required?: string[];
}

export interface FunctionDecl {
  name: string;
  description: string;
  parameters?: Schema & { type: "OBJECT" };
}

export type Generate = (req: { system: string; contents: Content[]; tools: FunctionDecl[] }) => Promise<Content>;

/** الحد المجاني انتهى (429) — رسالة واضحة للأدمن بدل خطأ عام. */
export class QuotaError extends Error {}

/** رفض من Google (مفتاح، صلاحية، منطقة، موديل…): الحالة ورسالة Google المختصرة. */
export class GeminiError extends Error {
  constructor(readonly status: number, readonly detail: string) {
    super(`Gemini ${status}: ${detail}`);
  }

  /** رسالة عربية للأدمن + سبب Google المختصر (ما بيه المفتاح). */
  get arabic(): string {
    const d = this.detail.toLowerCase();
    const why = d.includes("api key") || d.includes("api_key")
      ? "مفتاح Gemini غلط أو منتهي. اعمل مفتاح جديد من aistudio.google.com/apikey وحطه بالسيرفر."
      : d.includes("location") || d.includes("region")
        ? "Google ما تسمح بالخدمة من موقع السيرفر."
        : this.status === 403
          ? "Google رافضة الطلب: المفتاح ما عنده صلاحية على Gemini API."
          : this.status === 404
            ? "موديل Gemini المحدد غير موجود."
            : this.status >= 500
              ? "خدمة Gemini عليها ضغط هسه (جرّبنا الموديل الاحتياطي هم). جرّب بعد دقيقة."
              : "Google رفضت الطلب.";
    return `${why} (رمز ${this.status}: ${this.detail.slice(0, 160)})`;
  }
}

/** يقرأ رسالة الخطأ من رد Google. */
async function failure(res: Response): Promise<GeminiError> {
  const raw = await res.text();
  let detail = raw;
  try {
    detail = JSON.parse(raw)?.error?.message ?? raw;
  } catch { /* نص عادي */ }
  return new GeminiError(res.status, String(detail).replace(/\s+/g, " ").trim().slice(0, 300));
}

/** إعادة المحاولة عند ضغط Google المؤقت (500/502/503/504): مرتين لكل موديل، وبعدين الموديل الاحتياطي. */
const BUSY = new Set([500, 502, 503, 504]);
const RETRY_DELAY_MS = 700;

/**
 * السرعة: موديلات Flash الجديدة «تفكر» قبل كل رد (ثواني زايدة بكل جولة)، وأسئلة المساعد قراءة بيانات ما تحتاجه.
 * نطلب أقل تفكير؛ الصيغة تختلف بين الأجيال (Gemini 3: thinkingLevel، 2.5: thinkingBudget) والاسم «latest» يتغير،
 * فنجرب بالتسلسل: إذا الموديل رفض الصيغة (400 عن thinking) ننزل للي بعدها ونتذكرها لهذا الموديل.
 */
export const THINKING_LADDER: Array<Record<string, unknown> | null> = [{ thinkingLevel: "minimal" }, { thinkingBudget: 0 }, null];
const thinkingStep = new Map<string, number>();
/** للفحوص: ينسى الصيغ المحفوظة. */
export function resetThinkingMemory(): void {
  thinkingStep.clear();
}
/** توقيع وهمي رسمي من Google لتاريخ جاي من موديل ثاني (حتى الموديل الاحتياطي يقبل استدعاءات الأدوات السابقة). */
const FOREIGN_SIGNATURE = "skip_thought_signature_validator";

export interface CallOptions {
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  /** false = تفكير الموديل الافتراضي (أبطأ). الافتراضي: أقل تفكير. */
  fastThinking?: boolean;
}

/** يرسل لأول موديل يرد. يتذكر الموديل اللي اشتغل (sticky) لباقي جولات نفس السؤال. */
function caller(apiKey: string, models: string[], opts: CallOptions = {}) {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const fast = opts.fastThinking !== false;
  const lastStep = THINKING_LADDER.length - 1;
  let current = 0;
  return async (body: (model: string, switched: boolean, thinking: Record<string, unknown> | null) => unknown): Promise<Record<string, unknown>> => {
    let last: Error = new Error("no model");
    for (let i = current; i < models.length; i++) {
      for (let attempt = 0; attempt < 2; attempt++) {
        const step = fast ? (thinkingStep.get(models[i]) ?? 0) : lastStep;
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(models[i])}:generateContent`;
        const res = await fetchImpl(url, {
          method: "POST",
          headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify(body(models[i], i > 0, THINKING_LADDER[step])),
        });
        if (res.ok) {
          current = i;
          return await res.json();
        }
        if (res.status === 429) {
          await res.body?.cancel();
          last = new QuotaError("quota");
          break; // حد الموديل خلص: نجرب الاحتياطي (حده منفصل)
        }
        last = await failure(res);
        // الموديل ما يقبل صيغة التفكير هاي: نجرب اللي بعدها فوراً (مو محاولة محسوبة)
        if (res.status === 400 && step < lastStep && /think/i.test((last as GeminiError).detail)) {
          thinkingStep.set(models[i], step + 1);
          attempt--;
          continue;
        }
        if (!BUSY.has(res.status)) throw last;
        if (attempt === 0) await sleep(RETRY_DELAY_MS);
      }
    }
    throw last;
  };
}

/** [models]: الأساسي أولاً ثم الاحتياطي. */
export function geminiGenerate(apiKey: string, models: string | string[], fetchImplOrOpts: typeof fetch | CallOptions = {}): Generate {
  const opts = typeof fetchImplOrOpts === "function" ? { fetchImpl: fetchImplOrOpts } : fetchImplOrOpts;
  const call = caller(apiKey, Array.isArray(models) ? models : [models], opts);
  return async ({ system, contents, tools }) => {
    const data = await call((_, switched, thinking) => ({
      systemInstruction: { parts: [{ text: system }] },
      contents: switched ? withForeignSignatures(contents) : contents,
      tools: [{ functionDeclarations: tools }],
      generationConfig: { temperature: 0.2, ...(thinking ? { thinkingConfig: thinking } : {}) },
    }));
    // deno-lint-ignore no-explicit-any
    const content = (data as any)?.candidates?.[0]?.content as Content | undefined;
    if (!content?.parts?.length) {
      // حظر محتوى أو رد فارغ: نرجع نص بدل خطأ
      return { role: "model", parts: [{ text: "ما گدرت أجاوب على هذا الطلب. جرّب تكتبه بطريقة ثانية." }] };
    }
    return { role: "model", parts: content.parts };
  };
}

/** للموديل الاحتياطي: تواقيع الموديل الأساسي ما تنفعه، فنحط التوقيع الوهمي الرسمي على استدعاءات الأدوات. */
function withForeignSignatures(contents: Content[]): Content[] {
  return contents.map((c) => ({
    ...c,
    parts: c.parts.map((p) => ("functionCall" in p ? { ...p, thoughtSignature: FOREIGN_SIGNATURE } : p)),
  }));
}

/** صوت مسجّل (base64) بنوع يقبله Gemini. */
export interface AudioInput {
  mime: string;
  base64: string;
}

export type Transcribe = (audio: AudioInput, instruction: string) => Promise<string>;

/** نسخ الصوت لنص (Gemini يفهم الصوت مباشرة، ومنها اللهجة العراقية). */
export function geminiTranscribe(apiKey: string, models: string | string[], fetchImplOrOpts: typeof fetch | CallOptions = {}): Transcribe {
  const opts = typeof fetchImplOrOpts === "function" ? { fetchImpl: fetchImplOrOpts } : fetchImplOrOpts;
  const call = caller(apiKey, Array.isArray(models) ? models : [models], opts);
  return async (audio, instruction) => {
    const data = await call((_m, _s, thinking) => ({
      contents: [{ role: "user", parts: [{ text: instruction }, { inlineData: { mimeType: audio.mime, data: audio.base64 } }] }],
      generationConfig: { temperature: 0, ...(thinking ? { thinkingConfig: thinking } : {}) },
    }));
    // deno-lint-ignore no-explicit-any
    const parts = ((data as any)?.candidates?.[0]?.content?.parts ?? []) as Array<{ text?: string; thought?: boolean }>;
    return parts.filter((p) => p.text && !p.thought).map((p) => p.text).join("").trim();
  };
}
