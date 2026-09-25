'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { Loader2 } from 'lucide-react';

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    const checkAuth = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (session) {
          // Verify role in employee table
          const { data: emp } = await supabase
            .from('employees')
            .select('role')
            .eq('id', session.user.id)
            .single();

          if (emp && (emp.role === 'admin' || emp.role === 'manager')) {
            router.replace('/dashboard');
            return;
          }
        }
        router.replace('/login');
      } catch (err) {
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
