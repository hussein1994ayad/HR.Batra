'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  Coins, 
  Check, 
  X, 
  AlertCircle,
  TrendingUp,
  Loader2,
  Calendar,
  DollarSign,
  Settings,
  ArrowRightLeft,
  CreditCard,
  Save
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

export default function LoansPage() {
  const [loading, setLoading] = useState(true);
  const [loanRequests, setLoanRequests] = useState<any[]>([]);
  const [activeLoans, setActiveLoans] = useState<any[]>([]);
  const [approvalModal, setApprovalModal] = useState<any>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [editLoanModal, setEditLoanModal] = useState<any>(null);
  const [loansTab, setLoansTab] = useState<'active' | 'completed'>('active');

  // New States for Advanced Installment Management
  const [selectedLoanForInstallments, setSelectedLoanForInstallments] = useState<any>(null);
  const [cashPaymentPrompt, setCashPaymentPrompt] = useState<any>(null); // { installmentId, amount }
  const [cashNote, setCashNote] = useState('');
  const [editInstallmentPrompt, setEditInstallmentPrompt] = useState<any>(null); // { installmentId, amount }
  const [newInstallmentAmtVal, setNewInstallmentAmtVal] = useState(0);

  useEffect(() => {
    fetchLoanRequests();
  }, []);

  useEffect(() => {
    if (selectedLoanForInstallments) {
      const fresh = activeLoans.find(l => l.id === selectedLoanForInstallments.id);
      if (fresh) {
        setSelectedLoanForInstallments(fresh);
      } else {
        setSelectedLoanForInstallments(null);
      }
    }
  }, [activeLoans]);

  const fetchLoanRequests = async () => {
    setLoading(true);
    try {
      // Fetch pending loans and approved active loans concurrently using Promise.all
      const [
        { data: pending, error: pErr },
        { data: active, error: aErr }
      ] = await Promise.all([
        supabase
          .from('loans')
          .select('*, employees!loans_employee_id_fkey(full_name)')
          .eq('status', 'pending')
          .order('created_at', { ascending: false }),
        supabase
          .from('loans')
          .select('*, employees!loans_employee_id_fkey(full_name), loan_installments(*)')
          .eq('status', 'approved')
          .order('created_at', { ascending: false })
      ]);

      if (pending) setLoanRequests(pending);
      if (active) setActiveLoans(active);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleProcessLoan = async (loan: any, approve: boolean) => {
    if (approve) {
      const nextMonth = new Date();
      nextMonth.setMonth(nextMonth.getMonth() + 1);
      setApprovalModal({
        isOpen: true,
        loan,
        amount: Number(loan.amount),
        months: Number(loan.installment_count),
        startDate: nextMonth.toISOString().split('T')[0]
      });
      return;
    }

    setActionLoading(loan.id);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      const { error: updErr } = await supabase
        .from('loans')
        .update({
          status: 'rejected',
          approved_by: session.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', loan.id);

      if (updErr) throw updErr;

      await supabase.from('notifications').insert({
        employee_id: loan.employee_id,
        title: 'رفض طلب السلفة ❌',
        body: 'نأسف، تم رفض طلب السلفة المقدم من قبلك.',
        type: 'loan',
      });

      setLoanRequests(prev => prev.filter(req => req.id !== loan.id));
      toast.success('تم رفض طلب السلفة بنجاح. ❌');
    } catch (err: any) {
      toast.error(`فشل إتمام معالجة الطلب: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const submitSmartApproval = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!approvalModal) return;
    setActionLoading(approvalModal.loan.id);
    
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      const newAmount = Number(approvalModal.amount);
      const newMonths = Number(approvalModal.months);
      const installmentAmt = Math.round(newAmount / newMonths);

      const { error: updErr } = await supabase
        .from('loans')
        .update({
          status: 'approved',
          amount: newAmount,
          installment_count: newMonths,
          installment_amount: installmentAmt,
          approved_by: session.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', approvalModal.loan.id);

      if (updErr) throw updErr;

      const installments = [];
      let currentDueDate = new Date(approvalModal.startDate);

      for (let i = 0; i < newMonths; i++) {
        installments.push({
          loan_id: approvalModal.loan.id,
          due_date: currentDueDate.toISOString().split('T')[0],
          amount: installmentAmt,
          is_paid: false,
        });
        currentDueDate.setMonth(currentDueDate.getMonth() + 1);
      }

      const { error: instErr } = await supabase.from('loan_installments').insert(installments);
      if (instErr) throw instErr;

      await supabase.from('notifications').insert({
        employee_id: approvalModal.loan.employee_id,
        title: 'الموافقة على طلب السلفة 💸',
        body: `تم اعتماد سلفة بقيمة ${newAmount.toLocaleString()} د.ع وجدولتها بذكاء.`,
        type: 'loan',
      });

      setApprovalModal(null);
      fetchLoanRequests();
      confetti({ particleCount: 100, spread: 70, colors: ['#0D9488', '#34D399', '#6EE7B7'] });
      toast.success('تم اعتماد السلفة وتوليد الأقساط بذكاء! ✅');
    } catch (err: any) {
      toast.error(`فشل الاعتماد: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleSkipInstallment = async (loanId: string) => {
    if (!window.confirm('هل أنت متأكد من تخطي القسط لهذا الشهر؟ سيتم تأجيل جميع الدفعات المتبقية شهراً إضافياً.')) return;
    
    try {
      setActionLoading('skip_' + loanId);
      const { data: installments, error: getErr } = await supabase
        .from('loan_installments')
        .select('*')
        .eq('loan_id', loanId)
        .eq('is_paid', false)
        .order('due_date', { ascending: true });
        
      if (getErr || !installments || installments.length === 0) return;
      
      for (const inst of installments) {
        const oldDate = new Date(inst.due_date);
        oldDate.setMonth(oldDate.getMonth() + 1);
        await supabase
          .from('loan_installments')
          .update({ due_date: oldDate.toISOString().split('T')[0] })
          .eq('id', inst.id);
      }
      
      toast('تم تخطي القسط وتأجيل الدفعات القادمة بذكاء لمدة شهر! ✨');
      fetchLoanRequests();
    } catch (err) {
      toast.error('فشل تخطي القسط.');
    } finally {
      setActionLoading(null);
    }
  };

  const handleUpdateActiveLoan = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editLoanModal) return;
    setActionLoading('edit_' + editLoanModal.loan.id);
    
    try {
      const newAmount = Math.round(Number(editLoanModal.amount));
      const newInstallmentAmt = Math.round(Number(editLoanModal.installmentAmount));
      const newRemainingAmt = Math.round(Number(editLoanModal.remainingAmount));
      const newCount = Number(editLoanModal.installmentCount);

      // 1. Update details in loans table
      const { error: updErr } = await supabase
        .from('loans')
        .update({
          amount: newAmount,
          installment_amount: newInstallmentAmt,
          installment_count: newCount,
          remaining_amount: newRemainingAmt
        })
        .eq('id', editLoanModal.loan.id);

      if (updErr) throw updErr;

      // 2. Delete unpaid and regenerate them
      const { data: paidInst } = await supabase
        .from('loan_installments')
        .select('*')
        .eq('loan_id', editLoanModal.loan.id)
        .eq('is_paid', true);
        
      const paidCount = paidInst ? paidInst.length : 0;
      
      const { error: delErr } = await supabase
        .from('loan_installments')
        .delete()
        .eq('loan_id', editLoanModal.loan.id)
        .eq('is_paid', false);
        
      if (delErr) throw delErr;

      const remainingCount = newCount - paidCount;
      if (remainingCount > 0) {
        const installments = [];
        let currentDueDate = new Date();
        currentDueDate.setMonth(currentDueDate.getMonth() + 1);
        currentDueDate.setDate(1);
        
        for (let i = 0; i < remainingCount; i++) {
          installments.push({
            loan_id: editLoanModal.loan.id,
            due_date: currentDueDate.toISOString().split('T')[0],
            amount: newInstallmentAmt,
            is_paid: false,
          });
          currentDueDate.setMonth(currentDueDate.getMonth() + 1);
        }
        
        const { error: instErr } = await supabase.from('loan_installments').insert(installments);
        if (instErr) throw instErr;
      }

      await supabase.from('notifications').insert({
        employee_id: editLoanModal.loan.employee_id,
        title: 'تعديل تفاصيل السلفة 💸',
        body: `قامت الإدارة بتعديل تفاصيل سلفة العمل الخاصة بك (المبلغ الكلي الجديد: ${newAmount.toLocaleString()} د.ع، القسط الشهري الجديد: ${newInstallmentAmt.toLocaleString()} د.ع).`,
        type: 'loan',
      });

      setEditLoanModal(null);
      fetchLoanRequests();
      toast.success('تم تعديل السلفة وإعادة جدولة الأقساط المتبقية بنجاح! ✅');
    } catch (err: any) {
      toast.error(`فشل التعديل: ${err.message || err}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleRecordCashPayment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!cashPaymentPrompt) return;
    
    setActionLoading('cash_' + cashPaymentPrompt.installmentId);
    try {
      const { error } = await supabase
        .from('loan_installments')
        .update({
          is_paid: true,
          paid_at: new Date().toISOString(),
          payment_type: 'cash',
          payment_note: cashNote || 'سداد نقدي مباشر'
        })
        .eq('id', cashPaymentPrompt.installmentId);

      if (error) throw error;
      
      toast.success('تم تسجيل السداد النقدي وتحديث الرصيد المتبقي بنجاح! 💵');
      setCashPaymentPrompt(null);
      setCashNote('');
      fetchLoanRequests();
    } catch (err: any) {
      toast.error(`فشل تسجيل السداد: ${err.message || err}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleRevertPayment = async (installmentId: string) => {
    setActionLoading('revert_' + installmentId);
    try {
      const { error } = await supabase
        .from('loan_installments')
        .update({
          is_paid: false,
          paid_at: null,
          payment_type: 'salary_deduction',
          payment_note: null
        })
        .eq('id', installmentId);

      if (error) throw error;
      
      toast.success('تم التراجع عن السداد بنجاح! 🔄');
      fetchLoanRequests();
    } catch (err: any) {
      toast.error(`فشل التراجع عن السداد: ${err.message || err}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleDeletePaidInstallment = async (installmentId: string) => {
    if (!window.confirm('هل أنت متأكد من حذف هذا القسط المسدد نهائياً من قاعدة البيانات لتوفير المساحة؟ هذا الإجراء غير قابل للتراجع ولن يؤثر على رصيد السلفة المتبقي.')) return;
    
    setActionLoading('delete_inst_' + installmentId);
    try {
      const { error } = await supabase
        .from('loan_installments')
        .delete()
        .eq('id', installmentId);

      if (error) throw error;

      toast.success('تم حذف القسط المسدد نهائياً من قاعدة البيانات! 🗑️');
      
      if (selectedLoanForInstallments) {
        const updatedInsts = (selectedLoanForInstallments.loan_installments || []).filter((i: any) => i.id !== installmentId);
        setSelectedLoanForInstallments({
          ...selectedLoanForInstallments,
          loan_installments: updatedInsts
        });
      }
      
      fetchLoanRequests();
    } catch (err: any) {
      toast.error(`فشل حذف القسط: ${err.message || err}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleUpdateInstallmentAmount = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editInstallmentPrompt || newInstallmentAmtVal <= 0) return;
    
    setActionLoading('update_amt_' + editInstallmentPrompt.installmentId);
    try {
      const { error } = await supabase
        .from('loan_installments')
        .update({
          amount: newInstallmentAmtVal
        })
        .eq('id', editInstallmentPrompt.installmentId);

      if (error) throw error;
      
      toast.success('تم تعديل قيمة القسط وتحديث الرصيد المتبقي بنجاح! ✏️');
      setEditInstallmentPrompt(null);
      setNewInstallmentAmtVal(0);
      fetchLoanRequests();
    } catch (err: any) {
      toast.error(`فشل تعديل القسط: ${err.message || err}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handlePostponeInstallment = async (loanId: string, instId: string, instDueDate: string) => {
    setActionLoading('postpone_' + instId);
    try {
      // Fetch all unpaid installments for this loan that are due on or after this date
      const { data: installments, error: getErr } = await supabase
        .from('loan_installments')
        .select('*')
        .eq('loan_id', loanId)
        .eq('is_paid', false)
        .gte('due_date', instDueDate)
        .order('due_date', { ascending: true });
        
      if (getErr || !installments || installments.length === 0) return;
      
      for (const inst of installments) {
        const oldDate = new Date(inst.due_date);
        oldDate.setMonth(oldDate.getMonth() + 1);
        await supabase
          .from('loan_installments')
          .update({ due_date: oldDate.toISOString().split('T')[0] })
          .eq('id', inst.id);
      }
      
      toast.success('تم تأجيل القسط والأقساط اللاحقة شهراً إضافياً بنجاح! 🔄');
      fetchLoanRequests();
    } catch (err) {
      toast.error('فشل تأجيل القسط.');
    } finally {
      setActionLoading(null);
    }
  };

  const incompleteLoans = activeLoans.filter(l => Number(l.remaining_amount) > 0);
  const completedLoans = activeLoans.filter(l => Number(l.remaining_amount) <= 0);
  const displayedLoans = loansTab === 'active' ? incompleteLoans : completedLoans;

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
            <Coins className="w-5 h-5 text-teal-400" />
            <span>طلبات سلف الموظفين وتوليد الأقساط الشهرية</span>
          </h3>
          <p className="text-[11px] text-slate-400">اعتماد طلبات السلف المالية وتوليد أقساط وجداول السداد الشهرية بشكل مؤتمت وتفاعلي</p>
        </div>

        {loanRequests.length === 0 ? (
          <div className="h-64 flex flex-col items-center justify-center text-slate-500 text-xs">
            <Coins className="w-12 h-12 text-teal-500/20 mb-2 animate-pulse" />
            <span>لا توجد طلبات سلف معلقة للمراجعة حالياً. ✨</span>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {loanRequests.map((req) => {
              const amount = Number(req.amount);
              const months = Number(req.installment_count);
              const monthly = amount / months;
              
              return (
                <div 
                  key={req.id} 
                  className="relative bg-slate-950/40 border border-slate-850 hover:border-slate-800 rounded-2xl p-6 shadow-lg flex flex-col justify-between"
                >
                  <div className="space-y-4">
                    <div className="flex items-center justify-between border-b border-slate-900 pb-3">
                      <h4 className="font-extrabold text-sm text-white">{req.employees?.full_name || 'موظف'}</h4>
                      <span className="text-[10px] bg-teal-500/10 text-teal-300 font-bold border border-teal-500/20 px-2 py-0.5 rounded-full">
                        طلب سلفة مالية
                      </span>
                    </div>

                    <div className="grid grid-cols-2 gap-4 text-xs">
                      <div>
                        <span className="text-slate-500 text-[10px] block mb-0.5">قيمة السلفة الكلية</span>
                        <span className="text-white font-extrabold text-sm">{amount.toLocaleString()} د.ع</span>
                      </div>
                      <div>
                        <span className="text-slate-500 text-[10px] block mb-0.5">أشهر السداد المقترحة</span>
                        <span className="text-slate-300 font-bold">{months} شهر تقسيط</span>
                      </div>
                    </div>

                    <div className="p-4 bg-teal-950/10 border border-teal-500/10 rounded-2xl">
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-slate-400 font-semibold">القسط الشهري التلقائي:</span>
                        <span className="text-teal-400 font-extrabold text-sm">
                          {Math.round(monthly).toLocaleString()} د.ع / شهر
                        </span>
                      </div>
                    </div>

                    {req.pledge_url && (
                      <div className="p-3 bg-slate-900/60 rounded-xl border border-slate-850 flex items-center justify-between">
                        <span className="text-slate-400 text-xs font-semibold">التعهد الخطي الموقّع:</span>
                        <a 
                          href={req.pledge_url} 
                          target="_blank" 
                          rel="noreferrer"
                          className="text-[10px] bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 hover:border-teal-500/30 text-teal-300 font-bold px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
                        >
                          تحميل التعهد المالي 📄
                        </a>
                      </div>
                    )}
                  </div>

                  <div className="flex gap-3 pt-6 border-t border-slate-900 mt-6">
                    <button
                      disabled={actionLoading === req.id}
                      onClick={() => handleProcessLoan(req, true)}
                      className="flex-1 flex items-center justify-center gap-1.5 py-3 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/20 cursor-pointer"
                    >
                      <Settings className="w-4 h-4" />
                      <span>اعتماد وجدولة ذكية</span>
                    </button>
                    <button
                      disabled={actionLoading === req.id}
                      onClick={() => handleProcessLoan(req, false)}
                      className="flex-1 flex items-center justify-center gap-1.5 py-3 px-4 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-xs font-bold transition-all cursor-pointer"
                    >
                      <X className="w-4 h-4" />
                      <span>رفض الطلب</span>
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
        {/* Active & Completed Loans Section */}
        <div className="mt-12 pt-8 border-t border-slate-800/80">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6 border-b border-slate-800 pb-4">
            <div className="flex items-center gap-2">
              <CreditCard className="w-5 h-5 text-indigo-400" />
              <h3 className="text-lg font-extrabold text-white">
                {loansTab === 'active' ? 'إدارة السلف الجارية (النشطة)' : 'سجل السلف المكتملة المسددة'}
              </h3>
            </div>
            
            {/* Tab Bar (شريط التبويب) */}
            <div className="flex bg-slate-950 p-1 rounded-xl border border-slate-800">
              <button
                type="button"
                onClick={() => setLoansTab('active')}
                className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                  loansTab === 'active'
                    ? 'bg-teal-600 text-white shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                السلف الجارية ({incompleteLoans.length})
              </button>
              <button
                type="button"
                onClick={() => setLoansTab('completed')}
                className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                  loansTab === 'completed'
                    ? 'bg-teal-600 text-white shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                السلف المكتملة ({completedLoans.length})
              </button>
            </div>
          </div>
          
          <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
            <table className="w-full text-sm text-right">
              <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
                <tr>
                  <th className="px-4 py-4 font-bold">الموظف</th>
                  <th className="px-4 py-4 font-bold">المبلغ الكلي</th>
                  <th className="px-4 py-4 font-bold">المبلغ المتبقي (الأقساط)</th>
                  <th className="px-4 py-4 font-bold">القسط القادم</th>
                  <th className="px-4 py-4 font-bold text-center">الإجراءات الذكية</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 bg-slate-950/30">
                {displayedLoans.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-4 py-12 text-center text-slate-500 text-xs">
                      {loansTab === 'active' ? 'لا توجد سلف جارية حالياً' : 'لا توجد سلف مكتملة حالياً'}
                    </td>
                  </tr>
                ) : (
                  displayedLoans.map((loan) => {
                    const unpaid = (loan.loan_installments || []).filter((i: any) => !i.is_paid).sort((a: any, b: any) => new Date(a.due_date).getTime() - new Date(b.due_date).getTime());
                    const nextInstallment = unpaid.length > 0 ? unpaid[0] : null;
                    
                    return (
                      <tr key={loan.id} className="hover:bg-slate-900/40 transition-colors">
                        <td className="px-4 py-3 font-bold text-white text-xs">{loan.employees?.full_name}</td>
                        <td className="px-4 py-3 text-teal-400 font-bold text-xs">{Number(loan.amount).toLocaleString()} د.ع</td>
                        <td className="px-4 py-3 text-xs font-bold">
                          <div className="flex flex-col">
                            <span className={Number(loan.remaining_amount) > 0 ? 'text-amber-500 font-black text-xs' : 'text-emerald-400 font-black text-xs'}>
                              {Number(loan.remaining_amount).toLocaleString()} د.ع
                            </span>
                            <span className="text-[10px] text-slate-500">({unpaid.length} أقساط متبقية)</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-amber-400 text-xs font-mono">
                          {nextInstallment ? nextInstallment.due_date : 'اكتمل السداد ✨'}
                        </td>
                        <td className="px-4 py-3 flex items-center justify-center gap-2">
                          <button
                            type="button"
                            onClick={() => setSelectedLoanForInstallments(loan)}
                            className="px-3.5 py-2 bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 hover:border-teal-500/40 text-teal-400 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
                          >
                            <Calendar className="w-4 h-4" />
                            <span>جدول الأقساط والسداد</span>
                          </button>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>

      </div>

      {/* Smart Approval Modal */}
      {approvalModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <Settings className="w-5 h-5 text-teal-400" />
                <span>الاعتماد والجدولة الذكية للسلفة</span>
              </h3>
              <button onClick={() => setApprovalModal(null)} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
            </div>
            
            <form onSubmit={submitSmartApproval} className="space-y-4">
              <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
                <strong>الموظف:</strong> {approvalModal.loan.employees?.full_name}
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">المبلغ الإجمالي (د.ع)</label>
                <input 
                  type="text" 
                  value={approvalModal.amount}
                  onChange={(e) => setApprovalModal({ ...approvalModal, amount: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">عدد أشهر التقسيط</label>
                <input 
                  type="text" 
                  value={approvalModal.months}
                  onChange={(e) => setApprovalModal({ ...approvalModal, months: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="p-3 bg-teal-950/20 border border-teal-900/30 rounded-xl text-center">
                <span className="text-[10px] text-teal-500 block mb-1">القسط الشهري الجديد</span>
                <span className="text-lg font-black text-teal-400 font-mono">
                  {Math.round(approvalModal.amount / approvalModal.months).toLocaleString()} د.ع
                </span>
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">تاريخ استحقاق أول قسط (YYYY-MM-DD)</label>
                <input 
                  type="text" 
                  value={approvalModal.startDate}
                  onChange={(e) => setApprovalModal({ ...approvalModal, startDate: e.target.value })}
                  placeholder="2026-06-01"
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <button
                type="submit"
                disabled={actionLoading !== null}
                className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
              >
                {actionLoading !== null ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                <span>حفظ وتوليد الأقساط</span>
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Edit Active Loan Modal */}
      {editLoanModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl animate-glass">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <Settings className="w-5 h-5 text-blue-400" />
                <span>تعديل السلفة وإعادة الجدولة</span>
              </h3>
              <button onClick={() => setEditLoanModal(null)} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
            </div>
            
            <form onSubmit={handleUpdateActiveLoan} className="space-y-4">
              <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
                <strong>الموظف:</strong> {editLoanModal.loan.employees?.full_name}
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">المبلغ الإجمالي للسلفة (د.ع)</label>
                <input 
                  type="text" 
                  value={editLoanModal.amount}
                  onChange={(e) => setEditLoanModal({ ...editLoanModal, amount: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">القسط الشهري (د.ع)</label>
                <input 
                  type="text" 
                  value={editLoanModal.installmentAmount}
                  onChange={(e) => setEditLoanModal({ ...editLoanModal, installmentAmount: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">عدد الأقساط الإجمالي (أشهر)</label>
                <input 
                  type="text" 
                  value={editLoanModal.installmentCount}
                  onChange={(e) => setEditLoanModal({ ...editLoanModal, installmentCount: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">المبلغ المتبقي للسداد (د.ع)</label>
                <input 
                  type="text" 
                  value={editLoanModal.remainingAmount}
                  onChange={(e) => setEditLoanModal({ ...editLoanModal, remainingAmount: Number(e.target.value.replace(/\D/g, '')) })}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <button
                type="submit"
                disabled={actionLoading !== null}
                className="w-full mt-6 bg-blue-600 hover:bg-blue-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
              >
                {actionLoading !== null ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                <span>حفظ التعديلات وإعادة الجدولة</span>
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Installments & Repayment Schedule Modal */}
      {selectedLoanForInstallments && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/85 backdrop-blur-md p-4 overflow-y-auto">
          <div className="relative w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 text-right animate-glass my-8">
            <button 
              onClick={() => setSelectedLoanForInstallments(null)} 
              className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
            >
              ✕
            </button>

            <h3 className="text-md font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
              <Coins className="w-5 h-5 text-teal-400" />
              <span>جدول سداد وأقساط سلفة: {selectedLoanForInstallments.employees?.full_name}</span>
            </h3>

            {/* Loan Status Cards */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-slate-500 block mb-1">المبلغ الكلي للسلفة</span>
                <span className="text-xs font-black text-white">{Number(selectedLoanForInstallments.amount).toLocaleString()} د.ع</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-emerald-400 block mb-1">إجمالي ما تم سداده</span>
                <span className="text-xs font-black text-emerald-400">
                  {((Number(selectedLoanForInstallments.amount) - Number(selectedLoanForInstallments.remaining_amount)) || 0).toLocaleString()} د.ع
                </span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-amber-500 block mb-1">المبلغ المتبقي للسداد</span>
                <span className="text-xs font-black text-amber-500">{Number(selectedLoanForInstallments.remaining_amount).toLocaleString()} د.ع</span>
              </div>
              <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
                <span className="text-[10px] text-indigo-400 block mb-1">القسط الشهري الافتراضي</span>
                <span className="text-xs font-black text-indigo-400">{Number(selectedLoanForInstallments.installment_amount).toLocaleString()} د.ع</span>
              </div>
            </div>

            {/* Actions for Entire Loan */}
            <div className="flex gap-3 mb-6 bg-slate-950/20 p-3 rounded-2xl border border-slate-850 justify-between items-center">
              <span className="text-[10px] text-slate-400 font-bold">إجراءات السلفة العامة:</span>
              <div className="flex gap-2">
                <button
                  onClick={() => setEditLoanModal({
                    isOpen: true,
                    loan: selectedLoanForInstallments,
                    amount: Number(selectedLoanForInstallments.amount),
                    installmentAmount: Number(selectedLoanForInstallments.installment_amount),
                    installmentCount: Number(selectedLoanForInstallments.installment_count),
                    remainingAmount: Number(selectedLoanForInstallments.remaining_amount),
                  })}
                  className="px-3 py-1.5 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
                >
                  <Settings className="w-3.5 h-3.5" />
                  <span>تعديل السلفة وإعادة الجدولة</span>
                </button>
              </div>
            </div>

            {/* Installments Table */}
            <h4 className="text-xs font-bold text-slate-400 mb-3 flex items-center gap-1.5">
              <Calendar className="w-4 h-4 text-teal-400" />
              <span>تفاصيل الأقساط وجدول السداد:</span>
            </h4>

            <div className="overflow-y-auto max-h-[300px] border border-slate-800 rounded-2xl bg-slate-950/20 divide-y divide-slate-800/80">
              {(selectedLoanForInstallments.loan_installments || [])
                .sort((a: any, b: any) => new Date(a.due_date).getTime() - new Date(b.due_date).getTime())
                .map((inst: any, idx: number) => {
                  const isPaid = inst.is_paid;
                  
                  return (
                    <div key={inst.id} className="p-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs hover:bg-slate-900/40 transition-colors">
                      <div className="flex items-center gap-4">
                        <span className="font-bold text-slate-500 w-12">قسط #{idx + 1}</span>
                        <span className="font-mono text-slate-300 font-bold bg-slate-900 border border-slate-800 px-2 py-0.5 rounded-lg">{inst.due_date}</span>
                        <span className="font-bold text-white">{Number(inst.amount).toLocaleString()} د.ع</span>
                      </div>

                      <div className="flex items-center gap-3 justify-end">
                        {/* Status Badge */}
                        <span className={`px-2.5 py-1 rounded-xl font-bold text-[9px] ${
                          isPaid 
                            ? (inst.payment_type === 'cash' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/15' : 'bg-blue-500/10 text-blue-400 border border-blue-500/15')
                            : 'bg-slate-800 text-slate-400'
                        }`}>
                          {isPaid 
                            ? (inst.payment_type === 'cash' ? `مدفوع نقداً 💵 ${inst.payment_note ? `(${inst.payment_note})` : ''}` : 'مدفوع استقطاع راتب 💸')
                            : 'غير مدفوع ⏳'
                          }
                        </span>

                        {/* Actions */}
                        <div className="flex gap-1.5">
                          {!isPaid ? (
                            <>
                              <button
                                disabled={actionLoading !== null}
                                onClick={() => {
                                  setCashPaymentPrompt({ installmentId: inst.id, amount: inst.amount });
                                  setCashNote('');
                                }}
                                className="px-2 py-1 bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/20 text-emerald-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                                title="تسجيل سداد نقدي كاش خارج الراتب"
                              >
                                دفع نقدي 💵
                              </button>
                              <button
                                disabled={actionLoading !== null}
                                onClick={() => handlePostponeInstallment(selectedLoanForInstallments.id, inst.id, inst.due_date)}
                                className="px-2 py-1 bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/20 text-indigo-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                                title="تأجيل هذا القسط والأقساط اللاحقة شهراً إضافياً"
                              >
                                تأجيل قسط 🔄
                              </button>
                              <button
                                disabled={actionLoading !== null}
                                onClick={() => {
                                  setEditInstallmentPrompt({ installmentId: inst.id, amount: inst.amount });
                                  setNewInstallmentAmtVal(Number(inst.amount));
                                }}
                                className="px-2 py-1 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                                title="تعديل قيمة هذا القسط يدوياً"
                              >
                                تعديل ✏️
                              </button>
                            </>
                          ) : (
                            <div className="flex gap-1.5">
                              <button
                                disabled={actionLoading !== null}
                                onClick={() => {
                                  if (window.confirm('هل تريد إلغاء حالة السداد لهذا القسط وإعادته لغير مدفوع؟ سيتم إعادة إضافة القسط للمبلغ المتبقي ويستقطع مع الراتب القادم.')) {
                                    handleRevertPayment(inst.id);
                                  }
                                }}
                                className="px-2 py-1 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                                title="التراجع عن دفع القسط وإعادته لغير مدفوع"
                              >
                                تراجع عن الدفع 🔄
                              </button>
                              <button
                                type="button"
                                disabled={actionLoading !== null}
                                onClick={() => handleDeletePaidInstallment(inst.id)}
                                className="px-2 py-1 bg-red-500/15 hover:bg-red-650 border border-red-500/20 text-red-400 hover:text-white rounded-lg text-[10px] font-bold transition-all cursor-pointer flex items-center gap-1"
                                title="حذف القسط المسدد نهائياً من قاعدة البيانات لتوفير المساحة"
                              >
                                <span>حذف نهائي 🗑️</span>
                              </button>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
            </div>

            <div className="flex justify-end pt-6 mt-6 border-t border-slate-800">
              <button 
                onClick={() => setSelectedLoanForInstallments(null)}
                className="px-6 py-2.5 bg-slate-950 hover:bg-slate-900 text-white rounded-xl text-xs font-bold transition-all border border-slate-800 cursor-pointer"
              >
                موافق وإغلاق
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Record Cash Payment Prompt Modal */}
      {cashPaymentPrompt && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-glass text-right">
            <h3 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
              <Coins className="w-5 h-5 text-emerald-400" />
              <span>تسجيل سداد نقدي (كاش) للقسط</span>
            </h3>
            
            <form onSubmit={handleRecordCashPayment} className="space-y-4">
              <div className="p-3.5 bg-slate-950/50 rounded-xl text-xs text-slate-350 space-y-1">
                <p>• قيمة القسط المراد سداده: <span className="font-mono text-white font-bold">{Number(cashPaymentPrompt.amount).toLocaleString()} د.ع</span></p>
                <p className="text-[10px] text-amber-400">* سيتم خصم هذا القسط وتحديث رصيد السلفة فورياً وتخطيه في الراتب القادم.</p>
              </div>

              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">ملاحظات السداد (اختياري)</label>
                <input 
                  type="text" 
                  value={cashNote}
                  onChange={(e) => setCashNote(e.target.value)}
                  placeholder="مثال: دفع كاش بالكامل بوصل استلام يدوي"
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-xs focus:border-emerald-500/50 outline-none transition-all"
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800 mt-4">
                <button type="button" onClick={() => setCashPaymentPrompt(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
                <button
                  type="submit"
                  disabled={actionLoading !== null}
                  className="px-6 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 cursor-pointer"
                >
                  {actionLoading !== null ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>تأكيد السداد</span>}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Individual Installment Amount Modal */}
      {editInstallmentPrompt && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-glass text-right">
            <h3 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
              <Settings className="w-5 h-5 text-blue-400" />
              <span>تعديل قيمة قسط شهري</span>
            </h3>
            
            <form onSubmit={handleUpdateInstallmentAmount} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold">مبلغ القسط الجديد (د.ع)</label>
                <input 
                  type="text" 
                  value={newInstallmentAmtVal || ''}
                  onChange={(e) => setNewInstallmentAmtVal(Number(e.target.value.replace(/\D/g, '')))}
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
                  dir="ltr"
                  required
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800 mt-4">
                <button type="button" onClick={() => setEditInstallmentPrompt(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
                <button
                  type="submit"
                  disabled={actionLoading !== null}
                  className="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 cursor-pointer"
                >
                  {actionLoading !== null ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>حفظ التعديل</span>}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
