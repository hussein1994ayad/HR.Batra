'use client';

// المحادثات المحفوظة (فتح/حذف) + تشغيل الملخص الصباحي. المحادثات نص فقط وتنحذف تلقائياً بعد 90 يوم.

import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { History, MessageSquare, Trash2 } from 'lucide-react';
import { Button, EmptyState, IconButton, Modal, Toggle, cn } from '@/components/ui';
import { useConfirm } from '@/components/confirm';
import { formatDateTime } from '@/lib/format';
import { deleteConversation, getMorningSummary, listConversations, setMorningSummary } from '../api';
import type { SavedConversation } from '../types';

function HistoryModal({ currentId, onOpen, onClose }: { currentId: string | null; onOpen: (id: string) => void; onClose: () => void }) {
  const [items, setItems] = useState<SavedConversation[] | null>(null);
  const [failed, setFailed] = useState(false);
  const confirm = useConfirm();

  useEffect(() => {
    listConversations().then(setItems, () => setFailed(true));
  }, []);

  const remove = async (c: SavedConversation) => {
    if (!(await confirm({ title: 'حذف المحادثة؟', message: c.title, confirmLabel: 'حذف' }))) return;
    try {
      await deleteConversation(c.id);
      setItems((xs) => xs?.filter((x) => x.id !== c.id) ?? null);
    } catch {
      toast.error('ما انحذفت. جرّب مرة ثانية.');
    }
  };

  return (
    <Modal title="المحادثات السابقة" subtitle="تنحفظ نصوص المحادثات بس (بدون الملفات والصوت) وتنحذف بعد 90 يوم" icon={History} tone="violet" onClose={onClose}>
      {failed ? (
        <p className="text-sm text-rose-300">ما انقرت المحادثات. تأكد من الإنترنت.</p>
      ) : items === null ? (
        <p className="text-sm text-slate-400 animate-pulse">يحمّل…</p>
      ) : items.length === 0 ? (
        <EmptyState icon={MessageSquare} title="ماكو محادثات محفوظة بعد" description="كل سؤال تسأله ينحفظ هنا تلقائياً." />
      ) : (
        <ul className="divide-y divide-slate-800">
          {items.map((c) => (
            <li key={c.id} className="flex items-center gap-2 py-2">
              <button type="button" onClick={() => { onOpen(c.id); onClose(); }}
                className={cn('flex-1 text-right rounded-xl px-3 py-2 hover:bg-slate-800/60', c.id === currentId && 'bg-slate-800/40')}>
                <span className="block text-sm text-slate-100 line-clamp-2">{c.title}</span>
                <span className="block text-[11px] text-slate-500">{formatDateTime(c.updated_at)}</span>
              </button>
              <IconButton icon={Trash2} label="حذف" tone="rose" onClick={() => remove(c)} />
            </li>
          ))}
        </ul>
      )}
    </Modal>
  );
}

export function AssistantToolbar({ currentId, busy, onOpen }: { currentId: string | null; busy: boolean; onOpen: (id: string) => void }) {
  const [open, setOpen] = useState(false);
  const [summary, setSummary] = useState<boolean | null>(null);

  useEffect(() => {
    getMorningSummary().then(setSummary, () => setSummary(null));
  }, []);

  const toggle = async (on: boolean) => {
    try {
      await setMorningSummary(on);
      setSummary(on);
      toast.success(on ? 'الملخص الصباحي يوصلك كل يوم الساعة 10:00' : 'انطفى الملخص الصباحي');
    } catch {
      toast.error('ما تغيّر الإعداد. جرّب مرة ثانية.');
    }
  };

  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <Button variant="secondary" icon={History} onClick={() => setOpen(true)} disabled={busy}>المحادثات السابقة</Button>
      {summary !== null && (
        <Toggle checked={summary} onChange={toggle} label={<span className="text-xs text-slate-300">الملخص الصباحي (إشعار 10:00 بالموبايل)</span>} />
      )}
      {open && <HistoryModal currentId={currentId} onOpen={onOpen} onClose={() => setOpen(false)} />}
    </div>
  );
}
