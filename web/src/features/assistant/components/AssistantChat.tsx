'use client';

// واجهة المحادثة: الرسائل، الملفات (تنزيل)، الوثائق (فتح برابط موقّع)، والأسئلة الجاهزة.

import { useEffect, useRef, useState } from 'react';
import { FileSpreadsheet, FileText, Download, Send, Sparkles, MessageSquarePlus, Gavel } from 'lucide-react';
import { Button, Card, Textarea, cn } from '@/components/ui';
import { openStorageUrl } from '@/lib/signed-urls';
import { decidePayrollEvent } from '@/features/payroll/api';
import { EVENT_LABELS } from '@/features/payroll/calc';
import type { PayrollEventType } from '@/features/payroll/calc';
import { downloadBase64File } from '../api';
import { ASSISTANT_SUGGESTIONS, assistantDisplayText, decisionReason } from '../logic';
import type { AssistantAttachment, ChatMessage } from '../types';

/** بطاقة اقتراح قرار: ما ينفذ شي إلا لما الأدمن يضغط «تأكيد» (أو العكس)، وبعدها تنقفل. */
function DecisionCard({ d }: { d: Extract<AssistantAttachment, { kind: 'decision' }> }) {
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<boolean | null>(null);
  const [error, setError] = useState('');
  const suggestDeduct = d.suggest === 'deduct';
  const label = EVENT_LABELS[d.type as PayrollEventType] ?? d.type;
  const apply = async (deduct: boolean) => {
    setBusy(true);
    setError('');
    try {
      await decidePayrollEvent(d.event_id, deduct, decisionReason(suggestDeduct, d.reason, deduct));
      setDone(deduct);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ما تنفذ القرار.');
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="mt-3 rounded-2xl border border-slate-700 bg-slate-900/60 p-3 space-y-2 text-xs">
      <div className="flex items-center gap-2 text-slate-100">
        <Gavel className={cn('w-5 h-5', suggestDeduct ? 'text-rose-300' : 'text-emerald-300')} />
        <span className="font-bold">{d.employee} · {label} · {d.date}</span>
      </div>
      <p className="text-slate-400">{[d.minutes > 0 ? `${Math.round(d.minutes)} دقيقة` : '', d.amount > 0 ? `${Math.round(d.amount).toLocaleString('en-US')} د.ع` : '']
        .filter(Boolean).join(' · ')}</p>
      <p className="text-slate-200">الاقتراح: {suggestDeduct ? 'خصم' : 'إعفاء'} — {d.reason}</p>
      {done !== null ? (
        <p className={cn('font-bold', done ? 'text-rose-300' : 'text-emerald-300')}>{done ? '✓ تم الخصم' : '✓ تم الإعفاء'}</p>
      ) : (
        <div className="flex flex-wrap gap-2">
          <Button size="xs" variant={suggestDeduct ? 'danger' : 'primary'} loading={busy} onClick={() => apply(suggestDeduct)}>
            تأكيد {suggestDeduct ? 'خصم' : 'إعفاء'}
          </Button>
          <Button size="xs" variant="secondary" disabled={busy} onClick={() => apply(!suggestDeduct)}>
            {suggestDeduct ? 'إعفاء بدلاً منه' : 'خصم بدلاً منه'}
          </Button>
        </div>
      )}
      {error && <p className="text-rose-300">{error}</p>}
    </div>
  );
}

function Attachment({ a }: { a: AssistantAttachment }) {
  if (a.kind === 'decision') return <DecisionCard d={a} />;
  if (a.kind === 'file') {
    return (
      <div className="mt-3 flex items-center gap-3 rounded-2xl border border-slate-700 bg-slate-900/60 p-3">
        <FileSpreadsheet className="w-6 h-6 text-emerald-300 shrink-0" />
        <span className="flex-1 text-xs text-slate-200 break-all">{a.name}</span>
        <Button size="xs" variant="soft-success" icon={Download} onClick={() => downloadBase64File(a.name, a.mime, a.base64)}>
          تنزيل
        </Button>
      </div>
    );
  }
  return (
    <div className="mt-3 rounded-2xl border border-slate-700 bg-slate-900/60 divide-y divide-slate-800">
      {a.urls.map((url, i) => (
        <button key={url} type="button" onClick={() => openStorageUrl(url)}
          className="w-full flex items-center gap-3 p-3 text-xs text-slate-200 hover:bg-slate-800/60 text-right">
          <FileText className="w-5 h-5 text-indigo-300 shrink-0" />
          <span>وثيقة {i + 1} — {a.employee}</span>
        </button>
      ))}
    </div>
  );
}

function Bubble({ m }: { m: ChatMessage }) {
  const user = m.role === 'user';
  return (
    <div className={cn('flex', user ? 'justify-end' : 'justify-start')}>
      <div className={cn('max-w-[85%] rounded-3xl px-4 py-3 text-sm leading-7 whitespace-pre-line border',
        user ? 'bg-indigo-500/15 border-indigo-400/30 text-slate-100'
          : m.error ? 'bg-rose-950/40 border-rose-500/30 text-rose-200'
            : 'bg-slate-900/70 border-slate-800 text-slate-100')}>
        {user ? m.text : assistantDisplayText(m.text)}
        {m.attachments?.map((a, i) => <Attachment key={i} a={a} />)}
      </div>
    </div>
  );
}

export function AssistantChat({ messages, thinking, onSend, onReset }: {
  messages: ChatMessage[];
  thinking: boolean;
  onSend: (text: string) => void;
  onReset: () => void;
}) {
  const [draft, setDraft] = useState('');
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => end.current?.scrollIntoView({ behavior: 'smooth' }), [messages.length, thinking]);

  const submit = () => {
    if (!draft.trim() || thinking) return;
    onSend(draft);
    setDraft('');
  };

  return (
    <Card className="flex flex-col h-[calc(100vh-14rem)] min-h-[480px]" padded={false}>
      <div className="flex-1 overflow-y-auto p-5 space-y-3">
        {messages.length === 0 && (
          <div className="text-center py-8 space-y-4">
            <Sparkles className="w-12 h-12 mx-auto text-violet-300" />
            <p className="text-slate-300 text-sm">اسألني عن دوام أي موظف، الخصومات، السلف، الإجازات أو الوثائق، وأسويلك ملفات Excel.</p>
            <div className="flex flex-wrap justify-center gap-2">
              {ASSISTANT_SUGGESTIONS.map((s) => (
                <button key={s} type="button" onClick={() => onSend(s)}
                  className="px-3 py-1.5 rounded-full border border-slate-700 text-xs text-slate-300 hover:bg-slate-800">{s}</button>
              ))}
            </div>
          </div>
        )}
        {messages.map((m, i) => <Bubble key={i} m={m} />)}
        {thinking && <p className="text-xs text-slate-400 animate-pulse">يجهّز الجواب…</p>}
        <div ref={end} />
      </div>
      <div className="border-t border-slate-800 p-4 space-y-2">
        <div className="flex items-end gap-2">
          <Textarea rows={2} value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="اسأل عن موظف، دوام، خصومات، سلف…"
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); } }} aria-label="سؤالك" />
          <Button icon={Send} onClick={submit} disabled={thinking || !draft.trim()}>إرسال</Button>
          {messages.length > 0 && <Button variant="secondary" icon={MessageSquarePlus} onClick={onReset} disabled={thinking}>جديدة</Button>}
        </div>
        <p className="text-[11px] text-slate-500">يعمل بـ Gemini من Google · للقراءة فقط، ما يعدّل أي شي</p>
      </div>
    </Card>
  );
}
