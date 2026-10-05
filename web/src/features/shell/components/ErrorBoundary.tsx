'use client';

// يلتقط أي خطأ رسم داخل صفحات اللوحة ويعرض زر مسح الكاش وإعادة التحميل بدل شاشة بيضاء
// (كاش قديم بشكل مختلف كان أشيع سبب).

import React from 'react';
import { ShieldAlert } from 'lucide-react';
import { clearLocalCaches } from '@/lib/local-cache';

export class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { hasError: boolean; error: Error | null }
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error("Dashboard Boundary caught an error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="p-8 surface rounded-3xl text-right max-w-2xl mx-auto my-12 text-slate-100 animate-glass border-rose-500/30">
          <div className="flex items-center gap-3 mb-4">
            <div className="p-2.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400">
              <ShieldAlert className="w-5 h-5" />
            </div>
            <h2 className="text-lg font-bold text-rose-300">حدث خطأ غير متوقع في لوحة التحكم</h2>
          </div>
          <p className="text-sm text-slate-300 mb-6 leading-relaxed">
            لقد حدث خطأ أثناء معالجة أو عرض البيانات. يمكنك مسح البيانات المؤقتة وإعادة المحاولة بالضغط على الزر أدناه:
          </p>
          <pre className="p-4 bg-slate-950 rounded-2xl text-xs font-mono text-rose-300 overflow-x-auto whitespace-pre-wrap text-left mb-6 max-h-60 overflow-y-auto" dir="ltr">
            {this.state.error?.toString()}
            {"\n\nStack Trace:\n"}
            {this.state.error?.stack}
          </pre>
          <div className="flex flex-wrap gap-3">
            <button
              onClick={() => {
                clearLocalCaches();
                window.location.reload();
              }}
              className="px-5 py-2.5 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              مسح الذاكرة المؤقتة وإعادة التحميل
            </button>
            <button
              onClick={() => window.location.reload()}
              className="px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              إعادة المحاولة
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
