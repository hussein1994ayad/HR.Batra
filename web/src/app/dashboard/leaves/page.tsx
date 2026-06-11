'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  CalendarRange, 
  Check, 
  X, 
  Calendar,
  AlertTriangle,
  Loader2,
  FileText,
  User,
  ShieldCheck
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

export default function LeavesPage() {
  const [loading, setLoading] = useState(true);
  const [leaveRequests, setLeaveRequests] = useState<any[]>([]);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Tab State: pending, approved, rejected
  const [activeTab, setActiveTab] = useState<'pending' | 'approved' | 'rejected'>('pending');

  useEffect(() => {
    fetchLeaveRequests();
  }, [activeTab]);

  const fetchLeaveRequests = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('leave_requests')
        .select(`
          *, 
          employees!leave_requests_employee_id_fkey(full_name), 
          approver:employees!leave_requests_approved_by_fkey(full_name)
        `)
        .eq('status', activeTab)
        .order('created_at', { ascending: false });

      if (error) throw error;
      if (data) setLeaveRequests(data);
    } catch (err) {
      console.error('Error fetching leave requests:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleProcessLeave = async (requestId: string, employeeId: string, approve: boolean) => {
    setActionLoading(requestId);
    const statusText = approve ? 'approved' : 'rejected';
    
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      // 1. Update leave request record
      const { error: updErr } = await supabase
        .from('leave_requests')
        .update({
          status: statusText,
          approved_by: session.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', requestId);

      if (updErr) throw updErr;

      // 2. Broadcast live notification to employee
      const actionTitle = approve ? 'الموافقة على طلب إجازتك 🎉' : 'رفض طلب إجازتك ❌';
      const actionBody = approve 
          ? 'تهانينا! تمت الموافقة على طلب إجازتك المقدم مسبقاً.' 
          : 'نأسف لإعلامك بأنه تم رفض طلب إجازتك من قبل الإدارة.';

      await supabase.from('notifications').insert({
        employee_id: employeeId,
        title: actionTitle,
        body: actionBody,
        type: 'leave',
      });

      // Update state locally (remove from pending grid)
      setLeaveRequests(prev => prev.filter(req => req.id !== requestId));

      if (approve) {
        confetti({
          particleCount: 80,
          spread: 60,
          colors: ['#10B981', '#059669', '#34D399']
        });
      }

      toast.success(approve ? 'تمت الموافقة على طلب الإجازة بنجاح ✅' : 'تم رفض طلب الإجازة بنجاح ❌');
    } catch (err) {
      toast.error('فشل في معالجة طلب الإجازة');
    } finally {
      setActionLoading(null);
    }
  };

  const getLeaveTypeArabic = (type: string) => {
    switch (type) {
      case 'annual': return 'إجازة سنوية';
      case 'sick': return 'إجازة مرضية';
      case 'emergency': return 'إجازة طارئة';
      case 'maternity': return 'إجازة أمومة';
      default: return 'إجازة أخرى';
    }
  };

  return (
    <div className="space-y-8 pb-12">
      {/* Header and statistics */}
      <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h3 className="text-xl font-extrabold text-white flex items-center gap-2 mb-2">
            <CalendarRange className="w-6 h-6 text-teal-400" />
            <span>مركز إدارة الإجازات والغياب (Leaves Hub)</span>
          </h3>
          <p className="text-xs text-slate-400">إدارة واعتماد طلبات الإجازات المرفوعة ومراجعة الأرشيف التفصيلي للطلبات المعتمدة والمرفوضة</p>
        </div>

        {/* Tab Controls */}
        <div className="flex gap-2 p-1.5 bg-slate-950/40 border border-slate-850 rounded-2xl w-fit">
          <button
            onClick={() => setActiveTab('pending')}
            className={`px-4 py-2 text-xs font-bold rounded-xl transition-all cursor-pointer ${
              activeTab === 'pending'
                ? 'bg-teal-600/20 text-teal-400 border border-teal-500/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            الطلبات المعلقة ⏳
          </button>
          <button
            onClick={() => setActiveTab('approved')}
            className={`px-4 py-2 text-xs font-bold rounded-xl transition-all cursor-pointer ${
              activeTab === 'approved'
                ? 'bg-emerald-600/20 text-emerald-400 border border-emerald-500/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            الطلبات المعتمدة 🟢
          </button>
          <button
            onClick={() => setActiveTab('rejected')}
            className={`px-4 py-2 text-xs font-bold rounded-xl transition-all cursor-pointer ${
              activeTab === 'rejected'
                ? 'bg-rose-600/20 text-rose-400 border border-rose-500/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            الطلبات المرفوضة 🔴
          </button>
        </div>
      </div>

      {/* Main leaves grid */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl">
        {loading ? (
          <div className="h-64 flex items-center justify-center">
            <Loader2 className="w-8 h-8 text-teal-400 animate-spin" />
          </div>
        ) : leaveRequests.length === 0 ? (
          <div className="h-64 flex flex-col items-center justify-center text-slate-500 text-xs">
            <Calendar className="w-12 h-12 text-teal-500/20 mb-3 animate-pulse" />
            <span>لا توجد طلبات إجازة في هذا القسم حالياً. ✨</span>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 animate-fadeIn">
            {leaveRequests.map((req) => {
              const startDate = new Date(req.start_date);
              const endDate = new Date(req.end_date);
              const diffTime = Math.abs(endDate.getTime() - startDate.getTime());
              const totalDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;

              return (
                <div 
                  key={req.id} 
                  className="relative bg-slate-950/40 border border-slate-850 hover:border-slate-800 rounded-2xl p-6 shadow-lg flex flex-col justify-between"
                >
                  <div className="space-y-4 text-right">
                    <div className="flex items-center justify-between border-b border-slate-900 pb-3">
                      <h4 className="font-extrabold text-sm text-white">{req.employees?.full_name || 'موظف غير معروف'}</h4>
                      <span className="text-[9px] bg-teal-500/10 text-teal-300 font-bold border border-teal-500/20 px-2.5 py-0.5 rounded-full">
                        {getLeaveTypeArabic(req.leave_type)}
                      </span>
                    </div>

                    <div className="grid grid-cols-2 gap-4 text-xs font-medium">
                      <div>
                        <span className="text-slate-500 text-[10px] block mb-0.5">تاريخ البدء</span>
                        <span className="font-mono text-slate-300">{req.start_date.split('T')[0]}</span>
                      </div>
                      <div>
                        <span className="text-slate-500 text-[10px] block mb-0.5">تاريخ الانتهاء</span>
                        <span className="font-mono text-slate-300">{req.end_date.split('T')[0]}</span>
                      </div>
                    </div>

                    <div className="flex justify-between items-center text-xs bg-slate-900/40 p-2.5 rounded-xl border border-slate-850">
                      <span className="text-slate-400 font-semibold">إجمالي مدة الإجازة:</span>
                      <span className="text-teal-400 font-extrabold">{totalDays} يوم دوام</span>
                    </div>

                    {req.reason && (
                      <div className="p-3 bg-slate-900/60 rounded-xl border border-slate-850">
                        <span className="text-[10px] text-slate-500 block mb-1 flex items-center gap-1 justify-end">
                          <span>سبب تقديم الطلب</span>
                          <FileText className="w-3.5 h-3.5" />
                        </span>
                        <p className="text-xs text-slate-300 leading-relaxed font-medium">{req.reason}</p>
                      </div>
                    )}

                    {/* Historical Metadata info */}
                    {activeTab !== 'pending' && (
                      <div className="pt-3 border-t border-slate-900 mt-2 space-y-2 text-[10px] text-slate-400 font-medium">
                        <div className="flex items-center gap-1.5">
                          <ShieldCheck className="w-3.5 h-3.5 text-teal-500" />
                          <span>بواسطة المسؤول: <strong className="text-slate-300">{req.approver?.full_name || 'مدير النظام'}</strong></span>
                        </div>
                        <div className="flex items-center gap-1.5">
                          <User className="w-3.5 h-3.5 text-teal-500" />
                          <span>تاريخ القرار: <span className="font-mono text-slate-300">{new Date(req.approved_at).toLocaleString('ar-IQ')}</span></span>
                        </div>
                      </div>
                    )}
                  </div>

                  {activeTab === 'pending' ? (
                    <div className="flex gap-3 pt-6 border-t border-slate-900 mt-6">
                      <button
                        disabled={actionLoading === req.id}
                        onClick={() => handleProcessLeave(req.id, req.employee_id, true)}
                        className="flex-grow flex items-center justify-center gap-1.5 py-3 px-4 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-emerald-500/20 cursor-pointer"
                      >
                        <Check className="w-4 h-4" />
                        <span>الموافقة والاعتماد</span>
                      </button>
                      <button
                        disabled={actionLoading === req.id}
                        onClick={() => handleProcessLeave(req.id, req.employee_id, false)}
                        className="flex-grow flex items-center justify-center gap-1.5 py-3 px-4 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-xs font-bold transition-all cursor-pointer"
                      >
                        <X className="w-4 h-4" />
                        <span>رفض الطلب</span>
                      </button>
                    </div>
                  ) : (
                    <div className="pt-4 mt-4 border-t border-slate-900">
                      <div className={`py-2 rounded-xl text-center font-bold text-xs ${
                        activeTab === 'approved' 
                          ? 'bg-emerald-500/10 border border-emerald-500/15 text-emerald-400' 
                          : 'bg-rose-500/10 border border-rose-500/15 text-rose-400'
                      }`}>
                        {activeTab === 'approved' ? 'تمت الموافقة والاعتماد ✓' : 'تم رفض وإلغاء الطلب ❌'}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
