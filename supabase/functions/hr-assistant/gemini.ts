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

export interface FunctionDecl {
  name: string;
  description: string;
  parameters?: { type: "OBJECT"; properties: Record<string, { type: string; description: string }>; required?: string[] };
}

export type Generate = (req: { system: string; contents: Content[]; tools: FunctionDecl[] }) => Promise<Content>;

/** الحد المجاني انتهى (429) — رسالة واضحة للأدمن بدل خطأ عام. */
export class QuotaError extends Error {}

export function geminiGenerate(apiKey: string, model: string, fetchImpl: typeof fetch = fetch): Generate {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  return async ({ system, contents, tools }) => {
    const res = await fetchImpl(url, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents,
        tools: [{ functionDeclarations: tools }],
        generationConfig: { temperature: 0.2 },
      }),
    });
    if (res.status === 429) throw new QuotaError("quota");
    if (!res.ok) throw new Error(`Gemini ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const data = await res.json();
    const content = data?.candidates?.[0]?.content as Content | undefined;
    if (!content?.parts?.length) {
      // حظر محتوى أو رد فارغ: نرجع نص بدل خطأ
      return { role: "model", parts: [{ text: "ما گدرت أجاوب على هذا الطلب. جرّب تكتبه بطريقة ثانية." }] };
    }
    return { role: "model", parts: content.parts };
  };
}
