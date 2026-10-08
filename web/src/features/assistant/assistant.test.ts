import { describe, expect, it, vi } from 'vitest';

const invoke = vi.fn();
const rpc = vi.fn();
vi.mock('@/lib/supabase', () => ({
  supabase: { functions: { invoke: (...a: unknown[]) => invoke(...a) }, rpc: (...a: unknown[]) => rpc(...a) },
}));

import { askAssistant, historyFor, MAX_HISTORY, saveMessages } from './api';
import { clearAnnouncementDraft, peekAnnouncementDraft, stashAnnouncementDraft } from './draft';
import { assistantDisplayText, decisionReason } from './logic';
import type { ChatMessage } from './types';
import { bytesToBase64, encodeWav, micErrorMessage, WAV_SAMPLE_RATE } from './voice';

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

describe('assistant decision cards', () => {
  it('confirming the suggestion keeps its reason; choosing the opposite uses a plain reason', () => {
    expect(decisionReason(false, 'أول تأخير بالشهر', false)).toBe('أول تأخير بالشهر');
    expect(decisionReason(false, 'أول تأخير بالشهر', true)).toBe('بدون عذر');
    expect(decisionReason(true, 'متكرر', false)).toBe('عذر مقبول من الإدارة');
    expect(decisionReason(true, '  ', true)).toBe('بدون عذر');
  });
});

describe('assistant voice', () => {
  it('encodes mono 16kHz PCM WAV with a correct header and clipped samples', () => {
    const wav = encodeWav(new Float32Array([0, 1, -1, 2]));
    const v = new DataView(wav.buffer);
    expect(String.fromCharCode(...wav.subarray(0, 4))).toBe('RIFF');
    expect(String.fromCharCode(...wav.subarray(8, 12))).toBe('WAVE');
    expect(v.getUint16(22, true)).toBe(1);
    expect(v.getUint32(24, true)).toBe(WAV_SAMPLE_RATE);
    expect(v.getUint32(40, true)).toBe(8);
    expect(wav.length).toBe(52);
    expect([v.getInt16(44, true), v.getInt16(46, true), v.getInt16(48, true), v.getInt16(50, true)]).toEqual([0, 32767, -32768, 32767]);
  });

  it('base64 matches the standard encoding, also for large recordings', () => {
    expect(bytesToBase64(new Uint8Array([82, 73, 70, 70]))).toBe('UklGRg==');
    const big = new Uint8Array(100_000).map((_, i) => i % 256);
    expect(bytesToBase64(big)).toBe(Buffer.from(big).toString('base64'));
  });

  it('sends the recording with the conversation and returns what was understood', async () => {
    invoke.mockResolvedValueOnce({ data: { text: 'علي تأخر مرتين', transcript: ' شكد تأخر علي؟ ', attachments: [] }, error: null });
    const r = await askAssistant([], new Uint8Array([1, 2, 3]));
    expect(invoke).toHaveBeenLastCalledWith('hr-assistant', { body: { messages: [], audio: { mime: 'audio/wav', base64: 'AQID' } } });
    expect(r.transcript).toBe('شكد تأخر علي؟');
  });

  it('mic errors are explained in plain Arabic', () => {
    expect(micErrorMessage(new DOMException('x', 'NotAllowedError'))).toContain('فعّل المايكروفون');
    expect(micErrorMessage(new DOMException('x', 'NotFoundError'))).toBe('ماكو مايك متصل بالجهاز.');
    expect(micErrorMessage(new Error('x'))).toBe('ما اشتغل المايك. جرّب مرة ثانية.');
  });
});

describe('assistant history and drafts', () => {
  it('saves only text messages (no errors, no attachments) and keeps the voice flag', async () => {
    rpc.mockResolvedValueOnce({ data: 'c1', error: null });
    const id = await saveMessages(null, [
      { role: 'user', text: 'منو غايب؟', voice: true },
      { role: 'assistant', text: 'علي', attachments: [{ kind: 'file', name: 'a.xlsx', mime: 'x', base64: 'UEs=' }] },
      { role: 'assistant', text: 'خطأ', error: true },
    ]);
    expect(id).toBe('c1');
    expect(rpc).toHaveBeenCalledWith('assistant_save_messages', { p_conversation_id: null, p_messages: [
      { role: 'user', text: 'منو غايب؟', voice: true },
      { role: 'assistant', text: 'علي', voice: false },
    ] });
  });

  it('nothing to save: no request, same conversation', async () => {
    rpc.mockClear();
    expect(await saveMessages('c9', [{ role: 'assistant', text: 'x', error: true }])).toBe('c9');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('announcement drafts are handed to the dashboard and cleared after', () => {
    const store = new Map<string, string>();
    vi.stubGlobal('sessionStorage', {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => void store.set(k, v),
      removeItem: (k: string) => void store.delete(k),
    });
    expect(peekAnnouncementDraft()).toBeNull();
    stashAnnouncementDraft({ title: 'دوام العيد', body: 'الدوام الخميس.' });
    expect(peekAnnouncementDraft()).toEqual({ title: 'دوام العيد', body: 'الدوام الخميس.' });
    clearAnnouncementDraft();
    expect(peekAnnouncementDraft()).toBeNull();
    vi.unstubAllGlobals();
  });
});
