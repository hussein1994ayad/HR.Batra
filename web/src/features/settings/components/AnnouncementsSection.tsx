'use client';

import type { Announcement } from '@/lib/db-types';
import { Loader2, Trash2, Megaphone, Trash } from 'lucide-react';

interface AnnouncementsSectionProps {
  announcements: Announcement[];
  loadingAnnouncements: boolean;
  onDelete: (id: string) => void;
  onDeleteAll: () => void;
}

/** أرشيف التعاميم الإدارية مع الحذف الفردي أو الكامل. */
export function AnnouncementsSection({ announcements, loadingAnnouncements, onDelete, onDeleteAll }: AnnouncementsSectionProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 mt-8">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-3 border-b border-slate-850">
        <div className="flex items-center gap-2 text-teal-400">
          <Megaphone className="w-5 h-5" />
          <h4 className="text-sm font-extrabold text-white">أرشيف وإدارة التعاميم والإعلانات الإدارية</h4>
        </div>
        
        {announcements.length > 0 && (
          <button
            type="button"
            onClick={onDeleteAll}
            className="flex items-center justify-center gap-1.5 py-2 px-4 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-450 rounded-xl text-xs font-bold transition-all cursor-pointer"
          >
            <Trash className="w-4 h-4" />
            <span>إخلاء الأرشيف بالكامل 🧹</span>
          </button>
        )}
      </div>

      {loadingAnnouncements ? (
        <div className="flex justify-center p-6">
          <Loader2 className="w-6 h-6 text-teal-400 animate-spin" />
        </div>
      ) : announcements.length === 0 ? (
        <div className="text-center p-8 text-slate-500 text-xs">
          لا توجد أي تعاميم إدارية في الأرشيف حالياً
        </div>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
          <table className="w-full text-right border-collapse">
            <thead>
              <tr className="bg-slate-950/80 text-slate-300 text-xs font-bold border-b border-slate-800/80">
                <th className="p-3">تاريخ النشر</th>
                <th className="p-3">عنوان الإعلان</th>
                <th className="p-3">محتوى التعميم</th>
                <th className="p-3 text-left">الإجراءات</th>
              </tr>
            </thead>
            <tbody>
              {announcements.map((ann) => (
                <tr key={ann.id} className="border-b border-slate-800/40 hover:bg-slate-900/20 text-xs transition-colors">
                  <td className="p-3 text-slate-400 font-mono">
                    {new Date(ann.created_at).toLocaleDateString('ar-IQ', {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                      hour: '2-digit',
                      minute: '2-digit'
                    })}
                  </td>
                  <td className="p-3 font-bold text-white">
                    <div className="flex items-center gap-1.5">
                      <span>{ann.title}</span>
                      {ann.is_pinned && (
                        <span className="px-1.5 py-0.5 bg-teal-500/10 text-teal-400 border border-teal-500/15 rounded text-[8px] font-bold">مثبت</span>
                      )}
                    </div>
                  </td>
                  <td className="p-3 text-slate-350 max-w-sm truncate" title={ann.content}>
                    {ann.content}
                  </td>
                  <td className="p-3 text-left">
                    <button
                      type="button"
                      onClick={() => onDelete(ann.id)}
                      className="p-2 bg-slate-850 hover:bg-rose-500/10 hover:text-rose-400 border border-slate-800 hover:border-rose-500/20 text-slate-400 rounded-xl transition-all cursor-pointer"
                      title="حذف التعميم نهائياً"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
