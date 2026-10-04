'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { hasDashboardSession } from '@/features/auth/api';
import { Loader2 } from 'lucide-react';

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    const checkAuth = async () => {
      try {
        if (await hasDashboardSession()) {
          router.replace('/dashboard');
          return;
        }
        router.replace('/login');
      } catch (err) {
        console.error('Session check failed:', err);
        router.replace('/login');
      }
    };

    checkAuth();
  }, [router]);

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center bg-dark-bg text-white">
      <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-indigo-500/30 mb-5 animate-pulse">
        <Loader2 className="w-6 h-6 text-white animate-spin" />
      </div>
      <p className="text-sm font-bold text-slate-200">جاري التحميل...</p>
    </div>
  );
}
