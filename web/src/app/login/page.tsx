'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { errorMessage } from '@/lib/format';
import { Lock, Mail, AlertTriangle, ShieldCheck, Eye, EyeOff, Loader2, Sparkles, MapPin, CalendarRange, Banknote, ArrowLeft } from 'lucide-react';

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
        const { data: emp } = await supabase
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
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="relative min-h-dvh grid lg:grid-cols-2 bg-dark-bg overflow-hidden">
      {/* Brand panel */}
      <div className="relative hidden lg:flex flex-col justify-between p-12 overflow-hidden border-l border-slate-800/70 bg-gradient-to-bl from-indigo-600/30 via-slate-950 to-slate-950">
        <div className="absolute inset-0 bg-grid opacity-70 pointer-events-none" />
        <div className="absolute -top-32 -right-24 w-[420px] h-[420px] rounded-full bg-violet-500/25 blur-[120px] pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-[360px] h-[360px] rounded-full bg-indigo-500/20 blur-[120px] pointer-events-none" />

        <div className="relative flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-indigo-500/30">
            <Sparkles className="w-5 h-5 text-white" />
          </div>
          <span className="text-lg font-extrabold text-white">HR Pro</span>
        </div>

        <div className="relative max-w-md">
          <h2 className="text-4xl font-extrabold text-white leading-tight tracking-tight">
            إدارة الكادر،
            <br />
            <span className="bg-gradient-to-l from-indigo-300 to-fuchsia-300 bg-clip-text text-transparent">بوضوح وسرعة.</span>
          </h2>
          <p className="text-slate-400 mt-4 leading-relaxed">
            الحضور والتتبع الجغرافي، الإجازات، السلف والرواتب — كلها في لوحة واحدة متزامنة لحظياً.
          </p>

          <div className="mt-10 space-y-3">
            {[
              { icon: MapPin, text: 'تتبع الحضور بالسياج الجغرافي وكشف المواقع المزيفة' },
              { icon: CalendarRange, text: 'اعتماد الإجازات والسلف بنقرة واحدة' },
              { icon: Banknote, text: 'احتساب الرواتب والاستقطاعات تلقائياً' },
            ].map(({ icon: Icon, text }) => (
              <div key={text} className="flex items-center gap-3 text-sm text-slate-300">
                <div className="w-9 h-9 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-indigo-300">
                  <Icon className="w-4 h-4" />
                </div>
                {text}
              </div>
            ))}
          </div>
        </div>

        <p className="relative text-xs text-slate-500">© {new Date().getFullYear()} HR Pro — جميع الحقوق محفوظة</p>
      </div>

      {/* Form panel */}
      <div className="relative flex items-center justify-center p-6">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[420px] h-[420px] bg-indigo-600/10 rounded-full blur-[120px] pointer-events-none lg:hidden" />

        <div className="relative w-full max-w-sm animate-fade">
          <div className="lg:hidden flex items-center gap-3 mb-10">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-indigo-500/30">
              <Sparkles className="w-5 h-5 text-white" />
            </div>
            <span className="text-lg font-extrabold text-white">HR Pro</span>
          </div>

          <h1 className="text-2xl font-extrabold text-white tracking-tight">تسجيل الدخول</h1>
          <p className="text-slate-400 text-sm mt-1.5 mb-8">مرحباً بعودتك! أدخل بيانات حساب المسؤول للمتابعة.</p>

          {error && (
            <div className="flex items-start gap-3 p-3.5 bg-rose-500/10 border border-rose-500/20 rounded-xl text-rose-200 text-xs mb-6 animate-shake">
              <AlertTriangle className="w-4 h-4 text-rose-400 shrink-0 mt-0.5" />
              <p className="leading-relaxed font-medium">{error}</p>
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-5">
            <div>
              <label htmlFor="email" className="block text-slate-300 text-xs font-bold mb-2">
                البريد الإلكتروني
              </label>
              <div className="relative">
                <input
                  id="email"
                  type="email"
                  required
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@hrpro.com"
                  className="w-full h-12 bg-slate-900/70 border border-slate-800 hover:border-slate-700 focus:border-indigo-500 rounded-xl px-4 pr-11 text-sm text-white placeholder-slate-600 outline-none text-left"
                  dir="ltr"
                />
                <Mail className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
              </div>
            </div>

            <div>
              <label htmlFor="password" className="block text-slate-300 text-xs font-bold mb-2">
                كلمة المرور
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  required
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full h-12 bg-slate-900/70 border border-slate-800 hover:border-slate-700 focus:border-indigo-500 rounded-xl px-11 text-sm text-white placeholder-slate-600 outline-none text-left"
                  dir="ltr"
                />
                <Lock className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
                  className="absolute left-3 top-1/2 -translate-y-1/2 p-1 rounded-md text-slate-500 hover:text-slate-200 transition-colors cursor-pointer"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full h-12 flex items-center justify-center gap-2 bg-gradient-to-l from-indigo-500 to-violet-600 hover:from-indigo-400 hover:to-violet-500 text-white rounded-xl text-sm font-bold shadow-lg shadow-indigo-500/25 active:scale-[0.99] transition-all cursor-pointer disabled:opacity-60 disabled:pointer-events-none"
            >
              {loading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>جاري التحقق...</span>
                </>
              ) : (
                <>
                  <span>الدخول إلى لوحة التحكم</span>
                  <ArrowLeft className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          <div className="mt-8 flex items-center gap-2 text-[11px] text-slate-500">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-400/80" />
            اتصال مشفّر — الدخول متاح للمسؤولين والمدراء فقط
          </div>
        </div>
      </div>
    </div>
  );
}
