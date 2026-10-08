// طلب واحد للـ Edge Function `hr-assistant` (الذكاء والأدوات والإكسل بالسيرفر). السيرفر يتحقق إن المستخدم أدمن.

import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import type { AssistantReply, ChatMessage, SavedConversation } from './types';
import { bytesToBase64 } from './voice';

/** آخر 10 رسائل نصية تكفي للسياق (نفس حد السيرفر). */
export const MAX_HISTORY = 10;

/** اللي ينرسل للسيرفر: آخر الرسائل النصية بدون رسائل الخطأ والمرفقات. */
export function historyFor(conversation: ChatMessage[]): Array<{ role: ChatMessage['role']; text: string }> {
  return conversation
    .filter((m) => !m.error && m.text.trim())
    .slice(-MAX_HISTORY)
    .map(({ role, text }) => ({ role, text }));
}

/** يسأل المساعد. مع [wav]: السيرفر يكتب التسجيل نص (يرجع بـ transcript) ويجاوب عليه. */
export async function askAssistant(conversation: ChatMessage[], wav?: Uint8Array): Promise<AssistantReply> {
  const body: Record<string, unknown> = { messages: historyFor(conversation) };
  if (wav) body.audio = { mime: 'audio/wav', base64: bytesToBase64(wav) };
  const { data, error } = await supabase.functions.invoke('hr-assistant', { body });
  if (error) {
    let message = 'تعذّر الوصول للمساعد. تأكد من الإنترنت وجرّب مرة ثانية.';
    if (error instanceof FunctionsHttpError) {
      const body = await error.context.json().catch(() => null);
      if (body?.error) message = String(body.error);
    }
    throw new Error(message);
  }
  const transcript = typeof data?.transcript === 'string' && data.transcript.trim() ? data.transcript.trim() : undefined;
  return { text: String(data?.text ?? ''), transcript, attachments: Array.isArray(data?.attachments) ? data.attachments : [] };
}

// ---------------- المحادثات المحفوظة (نص فقط؛ الملفات والبطاقات والصوت ما تنحفظ) ----------------

/** يحفظ رسائل جديدة؛ بدون محادثة تنفتح وحدة جديدة. يرجع رقم المحادثة. */
export async function saveMessages(conversationId: string | null, messages: ChatMessage[]): Promise<string | null> {
  const rows = messages.filter((m) => !m.error && m.text.trim()).map((m) => ({ role: m.role, text: m.text, voice: !!m.voice }));
  if (!rows.length) return conversationId;
  const { data, error } = await supabase.rpc('assistant_save_messages', { p_conversation_id: conversationId, p_messages: rows });
  if (error) throw error;
  return data as string;
}

export async function listConversations(): Promise<SavedConversation[]> {
  const { data, error } = await supabase.from('assistant_conversations').select('id, title, updated_at')
    .order('updated_at', { ascending: false }).limit(50);
  if (error) throw error;
  return (data ?? []) as SavedConversation[];
}

export async function loadConversation(id: string): Promise<ChatMessage[]> {
  const { data, error } = await supabase.from('assistant_messages').select('role, text, voice').eq('conversation_id', id).order('id');
  if (error) throw error;
  return (data ?? []).map((m) => ({ role: m.role === 'user' ? 'user' : 'assistant', text: String(m.text), voice: !!m.voice }));
}

export async function deleteConversation(id: string): Promise<void> {
  const { error } = await supabase.from('assistant_conversations').delete().eq('id', id);
  if (error) throw error;
}

// ---------------- الملخص الصباحي (إشعار 10:00 للأدمن) ----------------

export async function getMorningSummary(): Promise<boolean> {
  const { data, error } = await supabase.rpc('assistant_settings');
  if (error) throw error;
  return (data as { morning_summary?: boolean } | null)?.morning_summary !== false;
}

export async function setMorningSummary(enabled: boolean): Promise<void> {
  const { error } = await supabase.rpc('assistant_set_morning_summary', { p_enabled: enabled });
  if (error) throw error;
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
