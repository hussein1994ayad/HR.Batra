'use client';

// حالة المحادثة. السؤال بالصوت: نص التسجيل يرجع من السيرفر وينضاف كرسالة الأدمن.
// كل سؤال وجوابه ينحفظ نص فقط بالخلفية (فشل الحفظ ما يوقف المحادثة)، و«المحادثات السابقة» تفتحها من جديد.

import { useRef, useState } from 'react';
import { askAssistant, loadConversation, saveMessages } from './api';
import type { ChatMessage } from './types';

export function useAssistant() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [thinking, setThinking] = useState(false);
  const [conversationId, setConversationId] = useState<string | null>(null);
  // الحفظات تمشي بالتسلسل حتى ما تنفتح محادثتين لنفس الكلام
  const saving = useRef<Promise<void>>(Promise.resolve());
  // كل «جديدة»/فتح محادثة = جيل جديد؛ كل جيل يحفظ بمحادثته (حتى لو الأدمن بدّل قبل ما يخلص الحفظ)
  const generation = useRef(0);
  const ids = useRef(new Map<number, string | null>());

  const save = (msgs: ChatMessage[]) => {
    const gen = generation.current;
    saving.current = saving.current.then(async () => {
      try {
        const id = await saveMessages(ids.current.get(gen) ?? null, msgs);
        ids.current.set(gen, id);
        if (gen === generation.current) setConversationId(id);
      } catch {
        /* الحفظ اختياري */
      }
    });
  };

  const ask = async (conversation: ChatMessage[], wav?: Uint8Array) => {
    setThinking(true);
    const question = !wav ? conversation.at(-1) : undefined;
    try {
      const reply = await askAssistant(conversation, wav);
      const heard: ChatMessage[] = wav && reply.transcript ? [{ role: 'user', text: reply.transcript, voice: true }] : [];
      const answer: ChatMessage = { role: 'assistant', text: reply.text, attachments: reply.attachments };
      setMessages((m) => [...m, ...heard, answer]);
      save([...(question ? [question] : []), ...heard, answer]);
    } catch (e) {
      setMessages((m) => [...m, { role: 'assistant', text: e instanceof Error ? e.message : 'صار خطأ. جرّب مرة ثانية.', error: true }]);
    } finally {
      setThinking(false);
    }
  };

  const send = async (raw: string) => {
    const text = raw.trim();
    if (!text || thinking) return;
    const next: ChatMessage[] = [...messages, { role: 'user', text }];
    setMessages(next);
    await ask(next);
  };

  const sendVoice = async (wav: Uint8Array) => {
    if (thinking) return;
    await ask(messages, wav);
  };

  const reset = () => {
    generation.current++;
    setMessages([]);
    setConversationId(null);
  };

  /** يفتح محادثة محفوظة (نص فقط). */
  const open = async (id: string) => {
    setThinking(true);
    try {
      const loaded = await loadConversation(id);
      generation.current++;
      ids.current.set(generation.current, id);
      setMessages(loaded);
      setConversationId(id);
    } finally {
      setThinking(false);
    }
  };

  return { messages, thinking, conversationId, send, sendVoice, reset, open };
}
