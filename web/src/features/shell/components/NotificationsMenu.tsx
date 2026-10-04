'use client';

// جرس الإشعارات بالرأس: عدّاد (طلبات إجازة + طلبات سلف معلّقة + إشعارات النظام غير المقروءة)
// وقائمة منسدلة تُغلق بالضغط خارجها.

import { useRef } from 'react';
import Link from 'next/link';
import { Bell, CalendarRange, CheckCheck, Coins, Inbox } from 'lucide-react';
import type { AppNotification } from '@/lib/db-types';
import { useClickOutside } from '@/lib/useClickOutside';

export function NotificationsMenu({
  open,
  onToggle,
  onClose,
  pendingLeaves,
  pendingLoans,
  systemNotifs,
  onMarkAllRead,
}: {
  open: boolean;
  onToggle: () => void;
  /** يجب أن يكون ثابتاً (useCallback) لأنه يدخل في مراقبة الضغط خارج القائمة */
  onClose: () => void;
  pendingLeaves: number;
  pendingLoans: number;
  systemNotifs: AppNotification[];
  onMarkAllRead: () => void;
}) {
  const notifRef = useRef<HTMLDivElement>(null);
  useClickOutside(notifRef, onClose, open);
  const totalNotifs = pendingLeaves + pendingLoans + systemNotifs.length;

  return (
    <div className="relative" ref={notifRef}>
      <button
        onClick={onToggle}
        className={`relative h-9 w-9 flex items-center justify-center rounded-xl border transition-colors cursor-pointer ${
          open
            ? 'bg-slate-800 border-slate-700 text-white'
            : 'bg-slate-900/60 border-slate-800 text-slate-400 hover:text-white hover:border-slate-700'
        }`}
        aria-label="الإشعارات"
      >
        <Bell className="w-[18px] h-[18px]" />
        {totalNotifs > 0 && (
          <span className="absolute -top-1.5 -left-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-slate-950" dir="ltr">
            {totalNotifs > 9 ? '9+' : totalNotifs}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-2 w-[min(22rem,calc(100vw-2rem))] surface-solid rounded-2xl shadow-2xl overflow-hidden z-50 text-right animate-glass">
          <div className="px-4 py-3 border-b border-slate-800/80 flex items-center justify-between">
            <h3 className="text-sm font-bold text-white">الإشعارات والمهام</h3>
            {systemNotifs.length > 0 && (
              <button
                onClick={onMarkAllRead}
                className="flex items-center gap-1 text-[11px] font-semibold text-indigo-300 hover:text-indigo-200 cursor-pointer"
              >
                <CheckCheck className="w-3.5 h-3.5" />
                تحديد الكل كمقروء
              </button>
            )}
          </div>
          <div className="p-2 max-h-96 overflow-y-auto">
            {totalNotifs === 0 ? (
              <div className="py-10 flex flex-col items-center text-center">
                <div className="p-3 rounded-2xl bg-slate-800/60 text-slate-500 mb-3"><Inbox className="w-6 h-6" /></div>
                <p className="text-xs font-semibold text-slate-300">لا توجد إشعارات جديدة</p>
                <p className="text-[11px] text-slate-500 mt-1">كل شيء على ما يرام</p>
              </div>
            ) : (
              <>
                {pendingLeaves > 0 && (
                  <Link href="/dashboard/leaves" onClick={onClose} className="flex items-center gap-3 p-3 hover:bg-slate-800/60 rounded-xl transition-colors">
                    <div className="p-2 bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-lg"><CalendarRange className="w-4 h-4" /></div>
                    <div className="flex-1">
                      <p className="text-xs font-bold text-white">طلبات إجازة معلقة</p>
                      <p className="text-[11px] text-slate-400">تحتاج إلى مراجعة واعتماد</p>
                    </div>
                    <span className="text-[11px] font-bold text-amber-300">{pendingLeaves}</span>
                  </Link>
                )}
                {pendingLoans > 0 && (
                  <Link href="/dashboard/loans" onClick={onClose} className="flex items-center gap-3 p-3 hover:bg-slate-800/60 rounded-xl transition-colors">
                    <div className="p-2 bg-teal-500/10 border border-teal-500/20 text-teal-400 rounded-lg"><Coins className="w-4 h-4" /></div>
                    <div className="flex-1">
                      <p className="text-xs font-bold text-white">طلبات سلف معلقة</p>
                      <p className="text-[11px] text-slate-400">بانتظار الاعتماد المالي</p>
                    </div>
                    <span className="text-[11px] font-bold text-teal-300">{pendingLoans}</span>
                  </Link>
                )}

                {systemNotifs.length > 0 && (
                  <div className="pt-2 mt-1 border-t border-slate-800/60">
                    <p className="text-[10px] text-slate-500 font-bold px-2 py-1.5">إشعارات النظام ({systemNotifs.length})</p>
                    {systemNotifs.map((notif, idx) => (
                      <div key={notif.id ?? idx} className="flex gap-2.5 p-3 hover:bg-slate-800/50 rounded-xl transition-colors">
                        <span className="mt-1.5 w-1.5 h-1.5 shrink-0 rounded-full bg-indigo-400" />
                        <div className="min-w-0">
                          <p className="text-xs font-bold text-white">{notif.title}</p>
                          <p className="text-[11px] text-slate-400 leading-relaxed mt-0.5">{notif.body}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
