'use client';

// حالة المحادثة (بالذاكرة فقط، ما تنحفظ).

import { useState } from 'react';
import { askAssistant } from './api';
import type { ChatMessage } from './types';

export function useAssistant() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [thinking, setThinking] = useState(false);

  const send = async (raw: string) => {
    const text = raw.trim();
    if (!text || thinking) return;
    const next: ChatMessage[] = [...messages, { role: 'user', text }];
    setMessages(next);
    setThinking(true);
    try {
      const reply = await askAssistant(next);
      setMessages((m) => [...m, { role: 'assistant', text: reply.text, attachments: reply.attachments }]);
    } catch (e) {
      setMessages((m) => [...m, { role: 'assistant', text: e instanceof Error ? e.message : 'صار خطأ. جرّب مرة ثانية.', error: true }]);
    } finally {
      setThinking(false);
    }
  };

  return { messages, thinking, send, reset: () => setMessages([]) };
}
