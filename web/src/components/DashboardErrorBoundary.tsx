'use client';

import React from 'react';

/**
 * DashboardErrorBoundary — يمسك الأخطاء غير المُتوقّعة في شجرة الـ dashboard
 * ويعرض شاشة استعادة نظيفة بدلاً من صفحة بيضاء.
 *
 * الاستخدام:
 *   <DashboardErrorBoundary>
 *     <YourDashboard />
 *   </DashboardErrorBoundary>
 *
 * ملاحظة: هذا Client Component، Class-based لأن Error Boundaries
 * في React 19 لا تزال تتطلب class components حتى الآن.
 */
export class DashboardErrorBoundary extends React.Component<
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
    console.error('Dashboard Boundary caught an error:', error, errorInfo);
  }

  private clearCacheAndReload = () => {
    try {
      localStorage.removeItem('batra_cache_dashboard');
      localStorage.removeItem('batra_cache_admin');
    } catch {
      // localStorage قد يفشل في وضع Private/Incognito — تجاهل
    }
    window.location.reload();
  };

  private reload = () => window.location.reload();

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <div className="p-8 bg-slate-900 border border-rose-500/30 rounded-3xl text-right max-w-2xl mx-auto my-12 text-slate-100 animate-glass">
        <div className="flex items-center gap-3 mb-4">
          <span className="text-2xl">⚠️</span>
          <h2 className="text-xl font-bold text-rose-400">
            حدث خطأ غير متوقع في لوحة التحكم
          </h2>
        </div>
        <p className="text-sm text-slate-300 mb-6 leading-relaxed">
          لقد حدث خطأ أثناء معالجة أو عرض البيانات. يمكنك مسح البيانات المؤقتة
          وإعادة المحاولة بالضغط على الزر أدناه:
        </p>
        <pre className="p-4 bg-slate-950 rounded-2xl text-xs font-mono text-rose-300 overflow-x-auto whitespace-pre-wrap text-left dir-ltr mb-6 max-h-60 overflow-y-auto">
          {this.state.error?.toString()}
          {'\n\nStack Trace:\n'}
          {this.state.error?.stack}
        </pre>
        <div className="flex gap-4">
          <button
            onClick={this.clearCacheAndReload}
            className="px-5 py-2.5 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
          >
            مسح الذاكرة المؤقتة وإعادة التحميل 🔄
          </button>
          <button
            onClick={this.reload}
            className="px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
          >
            إعادة محاولة التحميل 🔄
          </button>
        </div>
      </div>
    );
  }
}

export default DashboardErrorBoundary;
