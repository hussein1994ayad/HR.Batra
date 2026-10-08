'use client';

// حالة المحادثة (بالذاكرة فقط، ما تنحفظ). السؤال بالصوت: نص التسجيل يرجع من السيرفر وينضاف كرسالة الأدمن.

import { useState } from 'react';
import { askAssistant } from './api';
import type { ChatMessage } from './types';

export function useAssistant() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [thinking, setThinking] = useState(false);

  const ask = async (conversation: ChatMessage[], wav?: Uint8Array) => {
    setThinking(true);
    try {
      const reply = await askAssistant(conversation, wav);
      const heard: ChatMessage[] = wav && reply.transcript ? [{ role: 'user', text: reply.transcript, voice: true }] : [];
      setMessages((m) => [...m, ...heard, { role: 'assistant', text: reply.text, attachments: reply.attachments }]);
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

  return { messages, thinking, send, sendVoice, reset: () => setMessages([]) };
}
