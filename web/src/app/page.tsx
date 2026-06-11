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
    <div className="min-h-screen flex flex-col items-center justify-center bg-[#090D16] text-white">
      <div className="relative flex flex-col items-center p-8 bg-slate-900/40 backdrop-blur-xl border border-slate-800 rounded-3xl shadow-2xl">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-blue-500 rounded-t-3xl"></div>
        <Loader2 className="w-12 h-12 text-teal-400 animate-spin mb-4" />
        <h2 className="text-xl font-bold font-sans tracking-wide">جاري التحويل...</h2>
        <p className="text-slate-400 text-xs mt-2">تأمين اتصال لوحة التحكم HR Pro</p>
      </div>
    </div>
  );
}
