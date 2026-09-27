'use client';

import Image from 'next/image';
import { ExternalLink, FileImage } from 'lucide-react';
import { Modal } from '@/components/ui';
import { useSignedUrl } from '@/lib/signed-urls';

type Props = {
  previewDocUrl: string;
  previewDocTitle: string;
  onClose: () => void;
};

/** معاينة وثيقة (صورة أو PDF) بحجم كبير. */
export function DocumentPreviewModal({ previewDocUrl, previewDocTitle, onClose }: Props) {
  const isPdf = previewDocUrl.toLowerCase().includes('.pdf');
  const src = useSignedUrl(previewDocUrl);
  return (
    <Modal title={previewDocTitle} icon={FileImage} tone="teal" size="lg" onClose={onClose}>
      <div className="flex justify-end mb-3">
        <a
          href={src ?? undefined}
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg bg-slate-800/80 border border-slate-700/80 text-xs font-bold text-slate-100 hover:bg-slate-700/80"
        >
          <ExternalLink className="w-3.5 h-3.5" /> فتح في تبويب جديد
        </a>
      </div>
      <div className="flex items-center justify-center rounded-2xl bg-slate-950/60 p-2 min-h-[300px]">
        {!src ? (
          <p className="text-xs text-slate-500">جارٍ تحميل الوثيقة…</p>
        ) : isPdf ? (
          <iframe src={src} className="w-full h-[60vh] rounded-xl border border-slate-800" title="معاينة PDF" />
        ) : (
          <Image
            src={src}
            alt={previewDocTitle}
            width={1200}
            height={900}
            unoptimized
            className="max-h-[65vh] w-auto max-w-full object-contain rounded-xl"
          />
        )}
      </div>
    </Modal>
  );
}
