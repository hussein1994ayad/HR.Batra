// حلقة المحادثة: الذكاء يطلب أدوات ← ننفذها ← نرجّع النتائج ← لحد ما يكتب الجواب. مستقلة عن HTTP حتى تنفحص.

import type { Content, Generate } from "./gemini.ts";
import { runTool, TOOL_DECLS, type Attachment, type ToolContext } from "./tools.ts";

export const MAX_TOOL_ROUNDS = 6;
export const MAX_HISTORY = 10;

export interface ChatMessage {
  role: "user" | "assistant";
  text: string;
}

export interface AgentReply {
  text: string;
  attachments: Attachment[];
}

/** آخر الرسائل فقط، نص فقط (الملفات والوثائق ما ترجع للذكاء). */
export function toContents(history: ChatMessage[]): Content[] {
  return history
    .filter((m) => m && typeof m.text === "string" && m.text.trim())
    .slice(-MAX_HISTORY)
    .map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.text.slice(0, 4000) }] }));
}

export async function runAgent(opts: {
  generate: Generate;
  system: string;
  history: ChatMessage[];
  ctx: ToolContext;
}): Promise<AgentReply> {
  const contents = toContents(opts.history);
  const attachments: Attachment[] = [];

  for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
    const reply = await opts.generate({ system: opts.system, contents, tools: TOOL_DECLS });
    contents.push(reply);
    const calls = reply.parts.filter((p): p is Extract<typeof p, { functionCall: unknown }> => "functionCall" in p);
    if (!calls.length) {
      const text = reply.parts
        .filter((p): p is { text: string; thought?: boolean } => "text" in p && !p.thought)
        .map((p) => p.text).join("").trim();
      return { text: text || "تم.", attachments };
    }
    if (round === MAX_TOOL_ROUNDS) break;

    const responses = await Promise.all(calls.map(async ({ functionCall }) => {
      const result = await runTool(functionCall.name, functionCall.args ?? {}, opts.ctx);
      if (result.attachment) attachments.push(result.attachment);
      if (result.attachments) attachments.push(...result.attachments);
      return { functionResponse: { name: functionCall.name, response: result.forModel } };
    }));
    contents.push({ role: "user", parts: responses });
  }
  return { text: "الطلب احتاج خطوات كثيرة. جرّب تقسمه لأسئلة أصغر.", attachments };
}
