import { describe, expect, it, vi } from 'vitest';

const invoke = vi.fn();
vi.mock('@/lib/supabase', () => ({ supabase: { functions: { invoke: (...a: unknown[]) => invoke(...a) } } }));

import { askAssistant, historyFor, MAX_HISTORY } from './api';
import { assistantDisplayText } from './logic';
import type { ChatMessage } from './types';

describe('assistant', () => {
  it('sends only the last text messages, without errors or attachments', () => {
    const conv: ChatMessage[] = [
      ...Array.from({ length: 12 }, (_, i): ChatMessage => ({ role: i % 2 ? 'assistant' : 'user', text: `m${i}`,
        attachments: [{ kind: 'documents', employee: 'x', urls: ['u'] }] })),
      { role: 'assistant', text: 'خطأ', error: true },
      { role: 'user', text: '   ' },
    ];
    const h = historyFor(conv);
    expect(h).toHaveLength(MAX_HISTORY);
    expect(h[0]).toEqual({ role: 'user', text: 'm2' });
    expect(JSON.stringify(h)).not.toContain('urls');
    expect(h.some((m) => m.text === 'خطأ')).toBe(false);
  });

  it('calls the hr-assistant function and returns text + attachments', async () => {
    invoke.mockResolvedValueOnce({ data: { text: 'تم', attachments: [{ kind: 'file', name: 'a.xlsx', mime: 'x', base64: 'UEs=' }] }, error: null });
    const r = await askAssistant([{ role: 'user', text: 'سجل دوام علي' }]);
    expect(invoke).toHaveBeenCalledWith('hr-assistant', { body: { messages: [{ role: 'user', text: 'سجل دوام علي' }] } });
    expect(r.text).toBe('تم');
    expect(r.attachments[0]).toMatchObject({ kind: 'file', name: 'a.xlsx' });
  });

  it('a network failure becomes a clear Arabic message', async () => {
    invoke.mockResolvedValueOnce({ data: null, error: new Error('boom') });
    await expect(askAssistant([{ role: 'user', text: 'x' }])).rejects.toThrow('تعذّر الوصول للمساعد');
  });

  it('assistant text is cleaned for display', () => {
    expect(assistantDisplayText('## الملخص\n**الغياب:** 2\n- تأخير 30 د\n\n\n\nانتهى')).toBe('الملخص\nالغياب: 2\n• تأخير 30 د\n\nانتهى');
  });
});
