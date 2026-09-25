'use client';

import { X, FileImage, ExternalLink } from 'lucide-react';

interface DocumentPreviewModalProps {
  previewDocUrl: string;
  previewDocTitle: string;
  onClose: () => void;
}

/** معاينة وثيقة (صورة أو PDF) بحجم كبير. */
export function DocumentPreviewModal({ previewDocUrl, previewDocTitle, onClose }: DocumentPreviewModalProps) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/90 backdrop-blur-md">
      <div className="relative w-full max-w-3xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden max-h-[90vh] flex flex-col">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
          <h4 className="text-sm font-bold text-white flex items-center gap-2">
            <FileImage className="w-4 h-4 text-teal-400" />
            <span>{previewDocTitle}</span>
          </h4>
          <div className="flex items-center gap-2">
            <a
              href={previewDocUrl}
              target="_blank"
              rel="noreferrer"
              className="px-3 py-1.5 bg-teal-500/10 border border-teal-500/20 text-teal-400 hover:bg-teal-500/20 rounded-lg text-xs font-bold transition-all flex items-center gap-1"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              <span>فتح في تبويب جديد</span>
            </a>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-auto flex items-center justify-center bg-slate-950/60 rounded-2xl p-2 min-h-[300px]">
          {previewDocUrl.toLowerCase().includes('.pdf') ? (
            <iframe
              src={previewDocUrl}
              className="w-full h-[60vh] rounded-xl border border-slate-800"
              title="PDF Preview"
            />
          ) : (
            <img
              src={previewDocUrl}
              alt="Document Preview"
              className="max-h-[65vh] max-w-full object-contain rounded-xl shadow-lg"
            />
          )}
        </div>
      </div>
    </div>
  );
}
