// المساعد الذكي للأدمن — نفس شكل رد الـ Edge Function `hr-assistant` (supabase/functions/hr-assistant/agent.ts).

export type AssistantAttachment =
  | { kind: 'file'; name: string; mime: string; base64: string }
  | { kind: 'documents'; employee: string; urls: string[] };

export interface AssistantReply {
  text: string;
  attachments: AssistantAttachment[];
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
  attachments?: AssistantAttachment[];
  /** رسالة خطأ للعرض فقط (ما تنرسل للذكاء). */
  error?: boolean;
}
