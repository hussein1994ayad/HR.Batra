// المساعد الذكي للأدمن — نفس شكل رد الـ Edge Function `hr-assistant` (supabase/functions/hr-assistant/agent.ts).

export type AssistantAttachment =
  | { kind: 'file'; name: string; mime: string; base64: string }
  | { kind: 'documents'; employee: string; urls: string[] }
  /** اقتراح قرار: ما ينفذ إلا بزر «تأكيد» (decide_payroll_event). البيانات من القاعدة. */
  | { kind: 'decision'; event_id: string; employee: string; date: string; type: string; minutes: number; amount: number;
      suggest: 'deduct' | 'excuse'; reason: string }
  /** مسودة تعميم/رسالة: تُراجع وتُنشر يدوياً من نافذة التعاميم. */
  | { kind: 'draft'; draft_kind: 'announcement' | 'message'; title: string; body: string };

export interface AssistantReply {
  text: string;
  /** لسؤال بالصوت: شنو انفهم من التسجيل (يظهر كرسالة الأدمن). */
  transcript?: string;
  attachments: AssistantAttachment[];
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
  attachments?: AssistantAttachment[];
  /** رسالة خطأ للعرض فقط (ما تنرسل للذكاء). */
  error?: boolean;
  /** سؤال بالصوت (النص هو اللي انفهم من التسجيل). */
  voice?: boolean;
}

/** محادثة محفوظة (نص فقط، تنحذف بعد 90 يوم). */
export interface SavedConversation {
  id: string;
  title: string;
  updated_at: string;
}
