'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { Lock, Mail, AlertTriangle, ShieldCheck, Eye, EyeOff, Loader2 } from 'lucide-react';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Check if already authenticated
  useEffect(() => {
    const checkUser = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (session) {
        // Double check admin role
        const { data: emp, error: empErr } = await supabase
          .from('employees')
          .select('role')
          .eq('id', session.user.id)
          .single();

        if (emp && (emp.role === 'admin' || emp.role === 'manager')) {
          router.replace('/dashboard');
        }
      }
    };
    checkUser();
  }, [router]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      // 1. Sign in with Supabase auth
      const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (authErr) {
        throw new Error('بيانات الدخول غير صحيحة، يرجى التحقق وإعادة المحاولة.');
      }

      if (!authData.user) {
        throw new Error('فشل تسجيل الدخول.');
      }

      // 2. verify role in employees table (must be admin or manager)
      const { data: emp, error: empErr } = await supabase
        .from('employees')
        .select('role, full_name')
        .eq('id', authData.user.id)
        .single();

      if (empErr || !emp) {
        // Sign out if not an admin
        await supabase.auth.signOut();
        throw new Error('عذراً! لا تمتلك صلاحيات كافية للوصول إلى لوحة الإدارة.');
      }

      if (emp.role !== 'admin' && emp.role !== 'manager') {
        await supabase.auth.signOut();
        throw new Error('عذراً! هذا الحساب مخصص للموظفين فقط. لوحة الويب للمسؤولين فقط.');
      }

      // Redirect on success
      router.replace('/dashboard');
    } catch (err: any) {
      setError(err.message || 'حدث خطأ غير متوقع');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="relative min-h-screen flex items-center justify-center bg-[#090D16] p-4 overflow-hidden">
      {/* Background Radial Glow */}
      <div className="absolute top-1/4 left-1/4 w-[500px] h-[500px] bg-teal-500/10 rounded-full blur-[120px] pointer-events-none animate-pulse"></div>
      <div className="absolute bottom-1/4 right-1/4 w-[400px] h-[400px] bg-blue-500/10 rounded-full blur-[120px] pointer-events-none animate-pulse delay-700"></div>

      {/* Decorative Grid Pattern */}
      <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(15,23,42,0.1)_1px,transparent_1px),linear-gradient(to_bottom,rgba(15,23,42,0.1)_1px,transparent_1px)] bg-[size:4rem_4rem] pointer-events-none"></div>

      {/* Login Card */}
      <div className="relative w-full max-w-lg bg-slate-900/60 backdrop-blur-xl border border-slate-800 rounded-3xl p-8 md:p-12 shadow-2xl shadow-black/50 overflow-hidden">
        
        {/* Glow border header */}
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 via-blue-500 to-teal-500"></div>

        <div className="flex flex-col items-center mb-10 text-center">
          <div className="p-4 bg-teal-500/10 rounded-2xl border border-teal-500/20 mb-4 shadow-lg shadow-teal-500/5">
            <ShieldCheck className="w-12 h-12 text-teal-400" />
          </div>
          <h1 className="text-3xl font-extrabold tracking-tight text-white mb-2 font-sans">
            HR Pro v6.0
          </h1>
          <p className="text-slate-400 text-sm">
            لوحة الإدارة والمراقبة والتحليلات الجغرافية
          </p>
        </div>

        {error && (
          <div className="flex items-center gap-3 p-4 bg-red-500/10 border border-red-500/20 rounded-2xl text-red-200 text-sm mb-6 animate-shake">
            <AlertTriangle className="w-5 h-5 text-red-400 shrink-0" />
            <p className="leading-relaxed font-medium">{error}</p>
          </div>
        )}

        <form onSubmit={handleLogin} className="space-y-6">
          <div>
            <label className="block text-slate-300 text-xs font-semibold mb-2 pr-1">
              البريد الإلكتروني للأدمن
            </label>
            <div className="relative">
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@hrpro.com"
                className="w-full bg-slate-950/50 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-3.5 px-4 pr-11 text-white placeholder-slate-600 transition-all outline-none text-left"
                dir="ltr"
              />
              <Mail className="absolute left-auto right-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-500" />
            </div>
          </div>

          <div>
            <label className="block text-slate-300 text-xs font-semibold mb-2 pr-1">
              كلمة المرور
            </label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••••"
                className="w-full bg-slate-950/50 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-3.5 px-4 pr-11 text-white placeholder-slate-600 transition-all outline-none text-left"
                dir="ltr"
              />
              <Lock className="absolute left-auto right-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-500" />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-auto left-4 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300 transition-colors"
              >
                {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full flex items-center justify-center gap-2 py-4 px-6 bg-gradient-to-r from-teal-600 to-teal-500 hover:from-teal-500 hover:to-teal-400 text-white rounded-2xl font-bold shadow-lg shadow-teal-500/20 active:scale-[0.98] transition-all cursor-pointer disabled:opacity-50 disabled:pointer-events-none"
          >
            {loading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                <span>جاري تسجيل الدخول...</span>
              </>
            ) : (
              <span>الدخول للوحة التحكم ⚡</span>
            )}
          </button>
        </form>

        <div className="mt-8 text-center text-slate-500 text-xs">
          جميع الحقوق محفوظة © {new Date().getFullYear()} HR Pro v6.0
        </div>
      </div>
    </div>
  );
}
