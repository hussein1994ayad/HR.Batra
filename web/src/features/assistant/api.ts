// طلب واحد للـ Edge Function `hr-assistant` (الذكاء والأدوات والإكسل بالسيرفر). السيرفر يتحقق إن المستخدم أدمن.

import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import type { AssistantReply, ChatMessage } from './types';

/** آخر 10 رسائل نصية تكفي للسياق (نفس حد السيرفر). */
export const MAX_HISTORY = 10;

/** اللي ينرسل للسيرفر: آخر الرسائل النصية بدون رسائل الخطأ والمرفقات. */
export function historyFor(conversation: ChatMessage[]): Array<{ role: ChatMessage['role']; text: string }> {
  return conversation
    .filter((m) => !m.error && m.text.trim())
    .slice(-MAX_HISTORY)
    .map(({ role, text }) => ({ role, text }));
}

export async function askAssistant(conversation: ChatMessage[]): Promise<AssistantReply> {
  const { data, error } = await supabase.functions.invoke('hr-assistant', { body: { messages: historyFor(conversation) } });
  if (error) {
    let message = 'تعذّر الوصول للمساعد. تأكد من الإنترنت وجرّب مرة ثانية.';
    if (error instanceof FunctionsHttpError) {
      const body = await error.context.json().catch(() => null);
      if (body?.error) message = String(body.error);
    }
    throw new Error(message);
  }
  return { text: String(data?.text ?? ''), attachments: Array.isArray(data?.attachments) ? data.attachments : [] };
}

/** ينزّل ملف base64 من الرد (Excel) بنفس اسمه. */
export function downloadBase64File(name: string, mime: string, base64: string) {
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
